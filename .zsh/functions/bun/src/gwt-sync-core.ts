#!/usr/bin/env bun

/**
 * Git worktree 同步的生产核心：读取状态、构造未提交改动快照、预检冲突，
 * 并在显式授权后保护及恢复 dirty worktree
 */

import { randomUUID } from 'node:crypto'
import { existsSync, lstatSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, isAbsolute, join, relative, resolve } from 'node:path'

/** 解析 `git worktree list --porcelain -z` 的机器格式。 */
export function parseWorktreePorcelain(raw: string): WorktreeRecord[] {
  const records: WorktreeRecord[] = []
  let current: Partial<WorktreeRecord> = {}

  const finish = () => {
    if (!current.path || !current.head) {
      current = {}
      return
    }

    records.push({
      path: current.path,
      head: current.head,
      branch: current.branch,
      bare: current.bare ?? false,
      detached: current.detached ?? false,
      locked: current.locked,
      prunable: current.prunable,
    })
    current = {}
  }

  for (const field of raw.split('\0')) {
    if (!field) {
      finish()
      continue
    }

    const spaceIndex = field.indexOf(' ')
    const key = spaceIndex === -1 ? field : field.slice(0, spaceIndex)
    const value = spaceIndex === -1 ? '' : field.slice(spaceIndex + 1)

    switch (key) {
      case 'worktree':
        current.path = value
        break
      case 'HEAD':
        current.head = value
        break
      case 'branch':
        current.branch = value.replace(/^refs\/heads\//, '')
        break
      case 'bare':
        current.bare = true
        break
      case 'detached':
        current.detached = true
        break
      case 'locked':
        current.locked = value || 'locked'
        break
      case 'prunable':
        current.prunable = value || 'prunable'
        break
    }
  }

  finish()
  return records
}

/** 解析 NUL 分隔的 porcelain 状态，并分别统计暂存、未暂存和未跟踪项。 */
export function parseStatusPorcelain(raw: string): WorktreeStatus {
  let staged = 0
  let unstaged = 0
  let untracked = 0
  let entries = 0
  const tokens = raw.split('\0')

  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index]
    if (!token) continue

    const x = token[0]
    const y = token[1]
    entries++

    if (x === '?' && y === '?') {
      untracked++
      continue
    }

    if (x !== ' ' && x !== '?') staged++
    if (y !== ' ') unstaged++

    if (x === 'R' || x === 'C' || y === 'R' || y === 'C') index++
  }

  return {
    dirty: entries > 0,
    entries,
    staged,
    unstaged,
    untracked,
    raw,
  }
}

/** 按当前分支相对目标分支的提交数确定同步关系。 */
export function classifyRelation(ahead: number, behind: number): BranchRelation {
  if (ahead === 0 && behind === 0) return 'equal'
  if (ahead === 0) return 'behind'
  if (behind === 0) return 'ahead'
  return 'diverged'
}

/** 列出同一仓库注册的全部 worktree。 */
export function listWorktrees(repository: string): WorktreeRecord[] {
  return parseWorktreePorcelain(gitText(repository, [
    'worktree',
    'list',
    '--porcelain',
    '-z',
  ]))
}

/** 读取 worktree 的分支、工作区状态及进行中的 Git 操作。 */
export function inspectWorktree(worktree: string): WorktreeInspection {
  const branchResult = gitRaw(worktree, ['symbolic-ref', '--quiet', '--short', 'HEAD'])
  const branch = branchResult.exitCode === 0
    ? branchResult.stdout.trim()
    : undefined
  const head = gitText(worktree, ['rev-parse', 'HEAD']).trim()
  const statusRaw = gitText(worktree, [
    'status',
    '--porcelain=v1',
    '-z',
    '--untracked-files=all',
  ])

  return {
    branch,
    head,
    status: parseStatusPorcelain(statusRaw),
    operation: detectOperation(worktree),
  }
}

/** 返回当前分支相对目标提交的 ahead/behind 关系。 */
export function inspectRelation(worktree: string, target: string): RelationInspection {
  const output = gitText(worktree, [
    'rev-list',
    '--left-right',
    '--count',
    `HEAD...${target}`,
  ]).trim()
  const [aheadText, behindText] = output.split(/\s+/)
  const ahead = Number(aheadText)
  const behind = Number(behindText)

  if (!Number.isInteger(ahead) || !Number.isInteger(behind)) {
    throw new Error(`Unable to parse ahead/behind counts: ${output}`)
  }

  return {
    ahead,
    behind,
    relation: classifyRelation(ahead, behind),
  }
}

/**
 * 把真实 index 和完整工作区分别写成临时 commit
 *
 * 这些 commit 不更新任何引用，仅用于让 Git 原生三方合并算法理解未提交内容
 */
export function createWorktreeSnapshots(worktree: string): WorktreeSnapshots {
  const head = gitText(worktree, ['rev-parse', 'HEAD']).trim()
  const indexTree = gitText(worktree, ['write-tree']).trim()
  const indexCommit = createCommit(worktree, indexTree, head, 'gwt-sync index snapshot')
  const fullTree = writeFullWorktreeTree(worktree)
  const fullCommit = createCommit(worktree, fullTree, head, 'gwt-sync full snapshot')

  return {
    head,
    indexTree,
    fullTree,
    indexCommit,
    fullCommit,
  }
}

/**
 * 检查同步过程中会被写入的路径是否覆盖本地 ignored 文件
 *
 * 始终检查 `HEAD → target` 最终新增或发生类型变化的路径；rebase 还会检查
 * 每个候选重放提交曾经新增、重命名到或发生类型变化的路径，防止中间提交
 * 短暂覆盖 ignored 文件。只围绕候选路径检查，不枚举整个 ignored 文件集合，
 * 因此不会遍历无关的 `node_modules`
 *
 * @param options.strategy 同步策略；`rebase` 会启用逐提交检查
 */
export function findIgnoredPathConflicts(
  worktree: string,
  target: string,
  options: FindIgnoredPathConflictsOptions = {},
): IgnoredPathConflict[] {
  const strategy = options.strategy ?? 'merge'
  const materializedPaths = collectMaterializedPaths(worktree, target, strategy)
  const conflicts = new Map<string, IgnoredPathConflict>()

  const addConflict = (conflict: IgnoredPathConflict) => {
    const key = `${conflict.targetPath}\0${conflict.localPath}\0${conflict.relation}`
    conflicts.set(key, conflict)
  }

  for (const targetPath of materializedPaths) {
    const absoluteTarget = join(worktree, targetPath)
    const targetStat = safeLstat(absoluteTarget)

    if (targetStat && isIgnoredUntrackedPath(worktree, targetPath)) {
      addConflict({ targetPath, localPath: targetPath, relation: 'same-path' })
      continue
    }

    let parent = dirname(targetPath)
    while (parent !== '.') {
      const parentStat = safeLstat(join(worktree, parent))
      if (
        parentStat
        && !parentStat.isDirectory()
        && isIgnoredUntrackedPath(worktree, parent)
      ) {
        addConflict({ targetPath, localPath: parent, relation: 'local-parent' })
        break
      }
      const next = dirname(parent)
      if (next === parent) break
      parent = next
    }

    if (targetStat?.isDirectory()) {
      const descendants = gitRaw(worktree, [
        'ls-files',
        '--others',
        '--ignored',
        '--exclude-standard',
        '--directory',
        '-z',
        '--',
        `${targetPath}/`,
      ])
      if (descendants.exitCode !== 0) {
        throw new Error(`Unable to inspect ignored descendants: ${descendants.stderr.trim()}`)
      }

      const localPath = descendants.stdout.split('\0').find(Boolean)
      if (localPath) {
        addConflict({ targetPath, localPath, relation: 'local-descendant' })
      }
    }
  }

  return [...conflicts.values()]
}

/** 找出 `git stash` 无法可靠保存的 dirty submodule 或嵌套仓库。 */
export function findDirtyNestedRepositories(worktree: string): DirtyNestedRepository[] {
  const conflicts = new Map<string, DirtyNestedRepository>()
  const registeredSubmodules = new Set<string>()
  const indexEntries = gitText(worktree, ['ls-files', '--stage', '-z']).split('\0')

  for (const entry of indexEntries) {
    if (!entry) continue
    const tabIndex = entry.indexOf('\t')
    if (tabIndex === -1) continue
    const [mode, indexOid] = entry.slice(0, tabIndex).split(' ')
    if (mode !== '160000' || !indexOid) continue

    const path = entry.slice(tabIndex + 1)
    registeredSubmodules.add(path)
    const absolutePath = join(worktree, path)
    if (!existsSync(join(absolutePath, '.git'))) continue

    const childHead = gitRaw(absolutePath, ['rev-parse', 'HEAD'])
    const childStatus = gitRaw(absolutePath, [
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
      '--ignore-submodules=none',
    ])
    const headGitlink = gitRaw(worktree, ['rev-parse', `HEAD:${path}`])
    const reasons: string[] = []

    if (childHead.exitCode !== 0) reasons.push('Unable to read submodule HEAD')
    else if (childHead.stdout.trim() !== indexOid) reasons.push('Submodule HEAD does not match the index gitlink')

    if (headGitlink.exitCode !== 0 || headGitlink.stdout.trim() !== indexOid) {
      reasons.push('Index gitlink does not match the current commit')
    }
    if (childStatus.exitCode !== 0) reasons.push('Unable to read submodule status')
    else if (childStatus.stdout) reasons.push('Submodule contains uncommitted changes')

    if (reasons.length > 0) {
      conflicts.set(path, {
        path,
        kind: 'submodule',
        reason: reasons.join('; '),
      })
    }
  }

  const statusRaw = gitText(worktree, [
    'status',
    '--porcelain=v1',
    '-z',
    '--untracked-files=all',
    '--ignore-submodules=none',
  ])
  for (const statusPath of parseStatusPaths(statusRaw)) {
    const nestedRoot = findNestedRepositoryRoot(worktree, statusPath)
    if (!nestedRoot) continue
    if (
      [...registeredSubmodules].some((path) => (
        nestedRoot === path || nestedRoot.startsWith(`${path}/`)
      ))
    ) continue

    conflicts.set(nestedRoot, {
      path: nestedRoot,
      kind: 'nested-repository',
      reason: 'Superproject stash cannot safely preserve nested repository contents',
    })
  }

  return [...conflicts.values()]
}

/**
 * 在不移动真实分支的情况下预检同步
 *
 * merge/fast-forward 使用 `git merge-tree`；rebase 在临时 detached worktree 中
 * 实际重放 index 和完整工作区快照，因此能捕获中间提交冲突
 */
export function preflightUpdate(options: PreflightOptions): PreflightResult {
  const { worktree, target, strategy, snapshots } = options

  const ignoredConflicts = findIgnoredPathConflicts(worktree, target, { strategy })
  if (ignoredConflicts.length > 0) {
    return {
      ok: false,
      allowAttempt: false,
      details: formatIgnoredPathConflicts(ignoredConflicts),
    }
  }

  const nestedRepositories = findDirtyNestedRepositories(worktree)
  if (nestedRepositories.length > 0) {
    return {
      ok: false,
      allowAttempt: false,
      details: formatDirtyNestedRepositories(nestedRepositories),
    }
  }

  if (strategy === 'rebase') {
    const full = preflightRebaseSnapshot(worktree, snapshots.fullCommit, target)
    if (!full.ok) return full

    const index = preflightRebaseSnapshot(worktree, snapshots.indexCommit, target)
    if (!index.ok) {
      return {
        ...index,
        details: `The staged snapshot cannot be rebased without conflicts.\n${index.details}`,
      }
    }

    return {
      ok: true,
      expectedIndexTree: index.resultTree,
      expectedWorktreeTree: full.resultTree,
      details: 'Rebase preflight passed',
    }
  }

  const full = mergeTrees(worktree, snapshots.fullCommit, target)
  if (!full.ok) return full

  const index = mergeTrees(worktree, snapshots.indexCommit, target)
  if (!index.ok) {
    return {
      ...index,
      details: `The staged snapshot cannot be merged without conflicts.\n${index.details}`,
    }
  }

  return {
    ok: true,
    expectedIndexTree: index.resultTree,
    expectedWorktreeTree: full.resultTree,
    details: `${strategy} preflight passed`,
  }
}

/**
 * 执行已经通过预检的同步
 *
 * dirty worktree 仅在 `protectDirty` 为 true 时使用 stash；恢复成功且树对象校验
 * 一致后才删除 stash 和备份 ref。失败时保留二者供人工恢复
 */
export function executeUpdate(options: ExecuteUpdateOptions): ExecuteUpdateResult {
  const {
    worktree,
    sourceHead,
    sourceIndexTree,
    sourceWorktreeTree,
    target,
    targetLabel,
    strategy,
    branch,
    status,
    protectDirty,
    expectedIndexTree,
    expectedWorktreeTree,
    stdio = 'inherit',
  } = options

  if (status.dirty && !protectDirty) {
    throw new Error('Dirty worktrees require protection mode')
  }

  const currentInspection = inspectWorktree(worktree)
  if (currentInspection.branch !== branch) {
    throw new Error(`Branch changed from ${branch} to ${currentInspection.branch ?? '(detached)'}`)
  }
  if (currentInspection.head !== sourceHead) {
    throw new Error(`HEAD changed from ${sourceHead.slice(0, 12)} to ${currentInspection.head.slice(0, 12)}; rerun preflight`)
  }
  if (currentInspection.status.raw !== status.raw) {
    throw new Error('Worktree status changed after preflight; rerun preflight')
  }

  const currentIndexTree = gitText(worktree, ['write-tree']).trim()
  const currentWorktreeTree = writeFullWorktreeTree(worktree)
  if (
    currentIndexTree !== sourceIndexTree
    || currentWorktreeTree !== sourceWorktreeTree
  ) {
    throw new Error('Worktree content changed after preflight; rerun preflight')
  }

  const ignoredConflicts = findIgnoredPathConflicts(worktree, target, { strategy })
  if (ignoredConflicts.length > 0) {
    throw new Error(formatIgnoredPathConflicts(ignoredConflicts))
  }

  const nestedRepositories = findDirtyNestedRepositories(worktree)
  if (nestedRepositories.length > 0) {
    throw new Error(formatDirtyNestedRepositories(nestedRepositories))
  }

  const currentTarget = gitText(worktree, ['rev-parse', targetLabel]).trim()
  if (currentTarget !== target) {
    throw new Error(`${targetLabel} changed from ${target.slice(0, 12)} to ${currentTarget.slice(0, 12)}; rerun preflight`)
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
  const safeBranch = branch.replace(/[^A-Za-z0-9._/-]/g, '-').replace(/\/+/g, '/')
  const backupRef = `refs/gwt-sync-backup/${timestamp}/${safeBranch}`
  gitText(worktree, ['update-ref', backupRef, 'HEAD'])

  let stashOid: string | undefined
  if (status.dirty) {
    const previousStashOid = resolveOptionalRef(worktree, 'refs/stash')
    const stashMessage = `gwt-sync: ${branch} -> ${targetLabel} (${timestamp}, ${randomUUID()})`
    const stashResult = gitInherited(worktree, [
      'stash',
      'push',
      '--include-untracked',
      '--message',
      stashMessage,
    ], stdio)
    const currentStashOid = resolveOptionalRef(worktree, 'refs/stash')
    stashOid = findStashByMessage(worktree, stashMessage)
    if (
      stashResult !== 0
      || !currentStashOid
      || currentStashOid === previousStashOid
      || !stashOid
      || stashOid === previousStashOid
    ) {
      return {
        ok: false,
        stage: 'stash-create',
        backupRef,
        stashOid,
        details: 'Failed to save worktree changes; backup ref retained',
      }
    }
  }

  const updateCode = runUpdateCommand(worktree, target, targetLabel, branch, strategy, stdio)
  if (updateCode !== 0) {
    return {
      ok: false,
      stage: 'update',
      backupRef,
      stashOid,
      details: `${strategy} failed; no automatic abort was attempted; backup ref and stash retained`,
    }
  }

  if (stashOid) {
    const applyCode = gitInherited(worktree, ['stash', 'apply', '--index', stashOid], stdio)
    if (applyCode !== 0) {
      return {
        ok: false,
        stage: 'stash-apply',
        backupRef,
        stashOid,
        details: 'The branch was updated, but local changes could not be restored; stash and backup ref retained',
      }
    }
  }

  if (!expectedIndexTree || !expectedWorktreeTree) {
    return {
      ok: false,
      stage: 'manual-review',
      backupRef,
      stashOid,
      details: 'Update completed after conflict preflight failed; inspect the result manually; stash and backup ref retained',
    }
  }

  const actualIndexTree = gitText(worktree, ['write-tree']).trim()
  const actualWorktreeTree = writeFullWorktreeTree(worktree)
  if (
    actualIndexTree !== expectedIndexTree
    || actualWorktreeTree !== expectedWorktreeTree
  ) {
    return {
      ok: false,
      stage: 'verify',
      backupRef,
      stashOid,
      details: [
        'Updated content does not match the preflight result; all recovery refs were retained',
        `index: ${actualIndexTree.slice(0, 12)} != ${expectedIndexTree.slice(0, 12)}`,
        `worktree: ${actualWorktreeTree.slice(0, 12)} != ${expectedWorktreeTree.slice(0, 12)}`,
      ].join('\n'),
    }
  }

  if (stashOid) {
    const selector = findStashSelector(worktree, stashOid)
    if (!selector || gitInherited(worktree, ['stash', 'drop', selector], stdio) !== 0) {
      return {
        ok: false,
        stage: 'stash-drop',
        backupRef,
        stashOid,
        details: 'Content was restored, but the temporary stash could not be safely dropped; backup ref retained',
      }
    }
  }

  const cleanup = gitRaw(worktree, ['update-ref', '-d', backupRef])
  if (cleanup.exitCode !== 0) {
    return {
      ok: false,
      stage: 'backup-cleanup',
      backupRef,
      details: `Content was updated, but the backup ref could not be deleted: ${cleanup.stderr.trim()}`,
    }
  }
  return {
    ok: true,
    details: `${branch} updated to ${targetLabel} via ${strategy}`,
  }
}

/** 根据失败阶段和当前 Git 操作生成不会重复应用状态的恢复动作。 */
export function planRecovery(
  failure: ExecuteUpdateFailure,
  operation?: GitOperation,
): RecoveryAction[] {
  const actions: RecoveryAction[] = ['inspect-status']

  if (failure.stage === 'update') {
    if (operation === 'rebase') actions.push('abort-rebase')
    if (operation === 'merge') actions.push('abort-merge')
    if (failure.stashOid) actions.push('inspect-stash')
  }

  if (failure.stage === 'stash-create' && failure.stashOid) {
    actions.push('inspect-stash')
  }

  if (
    failure.stage === 'stash-apply'
    || failure.stage === 'manual-review'
    || failure.stage === 'verify'
  ) {
    actions.push('inspect-diff')
    if (failure.stashOid) actions.push('inspect-stash')
  }

  if (failure.stage === 'stash-drop') actions.push('inspect-stash')
  if (failure.backupRef) actions.push('inspect-backup')
  return actions
}

function detectOperation(worktree: string): GitOperation | undefined {
  const candidates: [GitOperation, string][] = [
    ['merge', 'MERGE_HEAD'],
    ['rebase', 'rebase-merge'],
    ['rebase', 'rebase-apply'],
    ['cherry-pick', 'CHERRY_PICK_HEAD'],
    ['revert', 'REVERT_HEAD'],
    ['bisect', 'BISECT_LOG'],
  ]

  for (const [operation, name] of candidates) {
    const path = gitRaw(worktree, ['rev-parse', '--git-path', name])
    const gitPath = path.stdout.trim()
    const absolutePath = isAbsolute(gitPath)
      ? gitPath
      : resolve(worktree, gitPath)
    if (path.exitCode === 0 && existsSync(absolutePath)) return operation
  }
  return undefined
}

function mergeTrees(worktree: string, snapshot: string, target: string): SnapshotPreflight {
  const result = gitRaw(worktree, [
    'merge-tree',
    '--write-tree',
    '--messages',
    '--name-only',
    '-z',
    snapshot,
    target,
  ])
  const parsed = parseMergeTreeOutput(result.stdout)
  const details = [
    ...parsed.messages,
    result.stderr,
  ].filter(Boolean).join('\n').trim()

  if (result.exitCode !== 0) {
    const allowAttempt = result.exitCode === 1
    return {
      ok: false,
      allowAttempt,
      conflictFiles: allowAttempt ? parsed.conflictFiles : undefined,
      conflictDiff: allowAttempt && parsed.resultTree
        ? createConflictDiff(worktree, snapshot, parsed.resultTree, parsed.conflictFiles)
        : undefined,
      details: details || 'git merge-tree detected a conflict',
    }
  }

  const resultTree = parsed.resultTree
  if (!resultTree) {
    return {
      ok: false,
      allowAttempt: false,
      details: `git merge-tree did not return a result tree:\n${details}`,
    }
  }

  return { ok: true, resultTree, details }
}

function preflightRebaseSnapshot(
  worktree: string,
  snapshot: string,
  target: string,
): SnapshotPreflight {
  const tempRoot = mkdtempSync(join(tmpdir(), 'gwt-sync-rebase-'))
  const checkout = join(tempRoot, 'checkout')
  let added = false

  try {
    const add = gitRaw(worktree, ['worktree', 'add', '--detach', checkout, snapshot])
    if (add.exitCode !== 0) {
      return {
        ok: false,
        allowAttempt: false,
        details: [add.stdout, add.stderr].filter(Boolean).join('\n').trim(),
      }
    }
    added = true

    // 预检必须零副作用：禁用 hooks，并阻止 rebase.updateRefs 改写重放范围内的其他本地分支
    const rebase = gitRaw(checkout, [
      '-c',
      'core.hooksPath=/dev/null',
      '-c',
      'rebase.updateRefs=false',
      'rebase',
      target,
    ])
    if (rebase.exitCode !== 0) {
      const conflicts = gitRaw(checkout, [
        'diff',
        '--name-only',
        '--diff-filter=U',
        '-z',
      ]).stdout.split('\0').filter(Boolean)
      return {
        ok: false,
        allowAttempt: conflicts.length > 0,
        conflictFiles: conflicts.length > 0 ? conflicts : undefined,
        conflictDiff: conflicts.length > 0
          ? createConflictDiff(checkout, undefined, undefined, conflicts)
          : undefined,
        details: [
          conflicts.length > 0 ? `Conflicting files:\n${conflicts.join('\n')}` : '',
          rebase.stdout,
          rebase.stderr,
        ].filter(Boolean).join('\n').trim(),
      }
    }

    const resultTree = gitText(checkout, ['rev-parse', 'HEAD^{tree}']).trim()
    return { ok: true, resultTree, details: rebase.stdout.trim() }
  }
  finally {
    if (added) gitRaw(worktree, ['worktree', 'remove', '--force', checkout])
    rmSync(tempRoot, { recursive: true, force: true })
  }
}

function parseMergeTreeOutput(raw: string): MergeTreeOutput {
  const tokens = raw.split('\0')
  const resultTree = /^[0-9a-f]{40,64}$/.test(tokens[0] ?? '')
    ? tokens[0]
    : undefined
  const conflictFiles: string[] = []
  const messages: string[] = []
  let index = 1

  while (index < tokens.length && tokens[index]) {
    conflictFiles.push(tokens[index])
    index++
  }
  index++

  while (index < tokens.length && tokens[index]) {
    const pathCount = Number(tokens[index++])
    if (!Number.isInteger(pathCount) || pathCount < 0) break

    index += pathCount
    const type = tokens[index++] ?? ''
    const message = tokens[index++] ?? ''
    if (message) messages.push(message)
    else if (type) messages.push(type)
  }

  return { resultTree, conflictFiles, messages }
}

function createConflictDiff(
  worktree: string,
  before: string | undefined,
  after: string | undefined,
  conflictFiles: string[],
): string | undefined {
  if (conflictFiles.length === 0) return undefined

  const args = [
    'diff',
    '--no-color',
    '--no-ext-diff',
  ]
  if (before && after) args.push(before, after)
  else args.push('--diff-filter=U')
  args.push('--', ...conflictFiles)

  const result = gitRaw(worktree, args)
  return result.exitCode === 0 && result.stdout
    ? result.stdout
    : undefined
}

function createCommit(
  worktree: string,
  tree: string,
  parent: string,
  message: string,
): string {
  return gitText(
    worktree,
    ['commit-tree', tree, '-p', parent],
    `${message}\n`,
    {
      GIT_AUTHOR_NAME: 'gwt-sync',
      GIT_AUTHOR_EMAIL: 'gwt-sync@local.invalid',
      GIT_COMMITTER_NAME: 'gwt-sync',
      GIT_COMMITTER_EMAIL: 'gwt-sync@local.invalid',
    },
  ).trim()
}

function writeFullWorktreeTree(worktree: string): string {
  const tempRoot = mkdtempSync(join(tmpdir(), 'gwt-sync-index-'))
  const tempIndex = join(tempRoot, 'index')
  const env = { GIT_INDEX_FILE: tempIndex }

  try {
    gitText(worktree, ['read-tree', 'HEAD'], undefined, env)
    gitText(worktree, ['add', '-A', '--', '.'], undefined, env)
    return gitText(worktree, ['write-tree'], undefined, env).trim()
  }
  finally {
    rmSync(tempRoot, { recursive: true, force: true })
  }
}

function runUpdateCommand(
  worktree: string,
  targetOid: string,
  targetLabel: string,
  branch: string,
  strategy: UpdateStrategy,
  stdio: GitStdio,
): number {
  switch (strategy) {
    case 'ff-only':
      return gitInherited(worktree, ['merge', '--ff-only', targetOid], stdio)
    case 'merge':
      return gitInherited(worktree, [
        'merge',
        '--no-edit',
        '--message',
        `Merge ${targetLabel} into ${branch}`,
        targetOid,
      ], stdio)
    case 'rebase':
      return gitInherited(worktree, ['rebase', targetOid], stdio)
  }
}

function findStashSelector(worktree: string, oid: string): string | undefined {
  const list = gitRaw(worktree, ['stash', 'list', '--format=%gd%x09%H'])
  if (list.exitCode !== 0) return undefined

  for (const line of list.stdout.split('\n')) {
    const [selector, hash] = line.split('\t')
    if (hash === oid) return selector
  }
  return undefined
}

function findStashByMessage(worktree: string, message: string): string | undefined {
  const list = gitRaw(worktree, ['stash', 'list', '--format=%H%x09%gs'])
  if (list.exitCode !== 0) return undefined

  for (const line of list.stdout.split('\n')) {
    const [oid, ...subjectParts] = line.split('\t')
    const subject = subjectParts.join('\t')
    if (oid && subject.endsWith(message)) return oid
  }
  return undefined
}

function resolveOptionalRef(worktree: string, ref: string): string | undefined {
  const result = gitRaw(worktree, ['rev-parse', '--verify', ref])
  return result.exitCode === 0 ? result.stdout.trim() : undefined
}

function collectMaterializedPaths(
  worktree: string,
  target: string,
  strategy: UpdateStrategy,
): string[] {
  const paths = new Set(
    gitText(worktree, [
      'diff',
      '--name-only',
      '-z',
      '--diff-filter=AT',
      '--no-renames',
      'HEAD',
      target,
    ]).split('\0').filter(Boolean),
  )

  if (strategy !== 'rebase') return [...paths]

  const replayCommits = gitText(worktree, [
    'rev-list',
    '--reverse',
    '--topo-order',
    '--no-merges',
    '--cherry-pick',
    '--right-only',
    `${target}...HEAD`,
  ]).split(/\r?\n/).filter(Boolean)

  if (replayCommits.length > 0) {
    const commitPaths = gitText(worktree, [
      'diff-tree',
      '--stdin',
      '--root',
      '--no-commit-id',
      '--name-only',
      '-z',
      '--diff-filter=AT',
      '--no-renames',
      '-r',
    ], `${replayCommits.join('\n')}\n`).split('\0').filter(Boolean)

    for (const path of commitPaths) paths.add(path)
  }

  return [...paths]
}

function isIgnoredUntrackedPath(worktree: string, path: string): boolean {
  const trackedEntries = gitText(worktree, [
    'ls-files',
    '--stage',
    '-z',
    '--',
    path,
  ]).split('\0').filter(Boolean)
  const tracked = trackedEntries.some((entry) => {
    const tabIndex = entry.indexOf('\t')
    return tabIndex !== -1 && entry.slice(tabIndex + 1) === path
  })

  return !tracked && isIgnoredPath(worktree, path)
}

function isIgnoredPath(worktree: string, path: string): boolean {
  const result = gitRaw(worktree, [
    'check-ignore',
    '--quiet',
    '--no-index',
    '--',
    path,
  ])
  if (result.exitCode === 0) return true
  if (result.exitCode === 1) return false
  throw new Error(`git check-ignore ${path} failed: ${result.stderr.trim()}`)
}

function safeLstat(path: string): ReturnType<typeof lstatSync> | undefined {
  try {
    return lstatSync(path)
  }
  catch (error) {
    if (
      error instanceof Error
      && 'code' in error
      && ['ENOENT', 'ENOTDIR'].includes((error as NodeJS.ErrnoException).code ?? '')
    ) return undefined
    throw error
  }
}

function parseStatusPaths(raw: string): string[] {
  const paths: string[] = []
  const tokens = raw.split('\0')

  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index]
    if (!token) continue
    const x = token[0]
    const y = token[1]
    paths.push(token.slice(3))
    if (x === 'R' || x === 'C' || y === 'R' || y === 'C') index++
  }
  return paths
}

function findNestedRepositoryRoot(worktree: string, statusPath: string): string | undefined {
  const root = resolve(worktree)
  let current = resolve(worktree, statusPath)
  if (!safeLstat(current)?.isDirectory()) current = dirname(current)

  while (current !== root && current.startsWith(`${root}/`)) {
    if (existsSync(join(current, '.git'))) {
      return relative(root, current).replaceAll('\\', '/')
    }
    const parent = dirname(current)
    if (parent === current) break
    current = parent
  }
  return undefined
}

function formatIgnoredPathConflicts(conflicts: IgnoredPathConflict[]): string {
  return [
    'The update would overwrite local ignored paths; operation blocked:',
    ...conflicts.map((conflict) => (
      `- ${conflict.targetPath} ← ${conflict.localPath} (${conflict.relation})`
    )),
  ].join('\n')
}

function formatDirtyNestedRepositories(conflicts: DirtyNestedRepository[]): string {
  return [
    'Unsafe nested repository state detected; superproject stash cannot preserve it:',
    ...conflicts.map((conflict) => (
      `- ${conflict.path} [${conflict.kind}]: ${conflict.reason}`
    )),
  ].join('\n')
}

function gitText(
  cwd: string,
  args: string[],
  input?: string,
  env?: Record<string, string>,
): string {
  const result = gitRaw(cwd, args, input, env)
  if (result.exitCode !== 0) {
    const message = [
      `git ${args.join(' ')} failed (exit ${result.exitCode})`,
      result.stderr,
      result.stdout,
    ].filter(Boolean).join('\n')
    throw new Error(message)
  }
  return result.stdout
}

function gitRaw(
  cwd: string,
  args: string[],
  input?: string,
  extraEnv?: Record<string, string>,
): GitResult {
  const result = Bun.spawnSync(['git', '-C', cwd, ...args], {
    stdin: input === undefined ? undefined : Buffer.from(input),
    stdout: 'pipe',
    stderr: 'pipe',
    env: { ...process.env, ...extraEnv },
  })

  return {
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  }
}

function gitInherited(cwd: string, args: string[], stdio: GitStdio = 'inherit'): number {
  if (stdio === 'capture') {
    return Bun.spawnSync(['git', '-C', cwd, ...args], {
      stdin: 'ignore',
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        GIT_TERMINAL_PROMPT: '0',
      },
    }).exitCode
  }

  return Bun.spawnSync(['git', '-C', cwd, ...args], {
    stdin: 'inherit',
    stdout: 'inherit',
    stderr: 'inherit',
  }).exitCode
}

/** 将目标提交整合进所选 worktree 分支的方式。 */
export type UpdateStrategy = 'ff-only' | 'merge' | 'rebase'

/** Git 子进程输出是继承终端，还是由调用方静默捕获。 */
export type GitStdio = 'inherit' | 'capture'

/** 当前分支相对目标提交的拓扑关系。 */
export type BranchRelation = 'equal' | 'ahead' | 'behind' | 'diverged'

/** 会阻止安全同步的进行中 Git 操作。 */
export type GitOperation = 'merge' | 'rebase' | 'cherry-pick' | 'revert' | 'bisect'

/** 失败后允许 CLI 展示的只读检查或与当前操作匹配的 abort 动作。 */
export type RecoveryAction =
  | 'inspect-status'
  | 'inspect-diff'
  | 'inspect-stash'
  | 'inspect-backup'
  | 'abort-merge'
  | 'abort-rebase'

/** `git worktree list` 中一个已注册 worktree 的稳定字段。 */
export interface WorktreeRecord {
  path: string
  head: string
  branch?: string
  bare: boolean
  detached: boolean
  locked?: string
  prunable?: string
}

/** worktree 中暂存、未暂存和未跟踪内容的计数及原始机器状态。 */
export interface WorktreeStatus {
  dirty: boolean
  entries: number
  staged: number
  unstaged: number
  untracked: number
  raw: string
}

/** 执行同步前读取的 worktree 快照信息。 */
export interface WorktreeInspection {
  branch?: string
  head: string
  status: WorktreeStatus
  operation?: GitOperation
}

/** 当前分支相对目标提交的 ahead/behind 结果。 */
export interface RelationInspection {
  ahead: number
  behind: number
  relation: BranchRelation
}

/** 未更新引用的临时 Git commit，用于预检 index 和完整工作区。 */
export interface WorktreeSnapshots {
  head: string
  indexTree: string
  fullTree: string
  indexCommit: string
  fullCommit: string
}

/** 目标树路径与本地 ignored 路径之间会被 checkout 覆盖的关系。 */
export interface IgnoredPathConflict {
  targetPath: string
  localPath: string
  relation: 'same-path' | 'local-parent' | 'local-descendant'
}

/** 调整 ignored 碰撞检查所覆盖的同步过程。 */
export interface FindIgnoredPathConflictsOptions {
  /**
   * 当前同步策略；rebase 会额外检查每个候选重放提交的中间路径
   *
   * @default 'merge'
   */
  strategy?: UpdateStrategy
}

/** `git stash` 无法作为 superproject 状态一部分保存的仓库边界。 */
export interface DirtyNestedRepository {
  path: string
  kind: 'submodule' | 'nested-repository'
  reason: string
}

/** 冲突预检所需的已固定输入。 */
export interface PreflightOptions {
  worktree: string
  target: string
  strategy: UpdateStrategy
  snapshots: WorktreeSnapshots
}

/** 预检成功，包含更新后应得到的 index 和完整工作区树。 */
export interface PreflightSuccess {
  ok: true
  expectedIndexTree: string
  expectedWorktreeTree: string
  details: string
}

/** 预检失败；只有普通 Git 冲突允许用户显式尝试真实更新。 */
export interface PreflightFailure {
  ok: false
  allowAttempt: boolean
  /** 预检确认存在冲突时涉及的路径；安全类失败可能没有具体文件。 */
  conflictFiles?: string[]
  /** 可交给 delta 等 diff renderer 的原始、无 ANSI Git diff。 */
  conflictDiff?: string
  expectedIndexTree?: undefined
  expectedWorktreeTree?: undefined
  details: string
}

/** 冲突和本地安全边界检查的预检结论。 */
export type PreflightResult = PreflightSuccess | PreflightFailure

/** 执行同步及恢复 dirty 状态所需的已预检输入。 */
export interface ExecuteUpdateOptions {
  worktree: string
  sourceHead: string
  sourceIndexTree: string
  sourceWorktreeTree: string
  target: string
  targetLabel: string
  strategy: UpdateStrategy
  branch: string
  status: WorktreeStatus
  protectDirty: boolean
  expectedIndexTree?: string
  expectedWorktreeTree?: string
  /**
   * Git 更新、stash 和恢复命令的输出方式；机器可读 CLI 应使用 `capture`
   *
   * @default 'inherit'
   */
  stdio?: GitStdio
}

/** 同步成功，临时 stash 和备份 ref 均已安全清理。 */
export interface ExecuteUpdateSuccess {
  ok: true
  details: string
}

/** 同步失败；`stage` 决定哪些恢复动作仍然安全。 */
export type ExecuteUpdateFailure =
  | StashCreateFailure
  | UpdateFailure
  | StashApplyFailure
  | ManualReviewFailure
  | VerifyFailure
  | StashDropFailure
  | BackupCleanupFailure

/** 同步执行的阶段化结果。 */
export type ExecuteUpdateResult = ExecuteUpdateSuccess | ExecuteUpdateFailure

interface ExecuteUpdateFailureBase {
  ok: false
  details: string
  backupRef?: string
  stashOid?: string
}

interface StashCreateFailure extends ExecuteUpdateFailureBase {
  stage: 'stash-create'
}

interface UpdateFailure extends ExecuteUpdateFailureBase {
  stage: 'update'
}

interface StashApplyFailure extends ExecuteUpdateFailureBase {
  stage: 'stash-apply'
  stashOid: string
}

interface ManualReviewFailure extends ExecuteUpdateFailureBase {
  stage: 'manual-review'
}

interface VerifyFailure extends ExecuteUpdateFailureBase {
  stage: 'verify'
}

interface StashDropFailure extends ExecuteUpdateFailureBase {
  stage: 'stash-drop'
  stashOid: string
}

interface BackupCleanupFailure extends ExecuteUpdateFailureBase {
  stage: 'backup-cleanup'
  backupRef: string
}

interface SnapshotPreflightSuccess {
  ok: true
  resultTree: string
  details: string
}

interface SnapshotPreflightFailure {
  ok: false
  allowAttempt: boolean
  conflictFiles?: string[]
  conflictDiff?: string
  details: string
}

type SnapshotPreflight = SnapshotPreflightSuccess | SnapshotPreflightFailure

interface MergeTreeOutput {
  resultTree?: string
  conflictFiles: string[]
  messages: string[]
}

interface GitResult {
  exitCode: number
  stdout: string
  stderr: string
}
