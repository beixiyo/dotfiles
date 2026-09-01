#!/usr/bin/env bun

/**
 * `gwt-sync` 机器模式：把显式 worktree 和远程分支解析为固定快照，
 * 复用生产核心完成只读预检或经授权的更新，并返回稳定的 JSON 数据结构
 */

import { existsSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  createWorktreeSnapshots,
  executeUpdate,
  type ExecuteUpdateFailure,
  inspectRelation,
  inspectWorktree,
  listWorktrees,
  planRecovery,
  preflightUpdate,
  type RelationInspection,
  type UpdateStrategy,
  type WorktreeInspection,
  type WorktreeRecord,
} from './gwt-sync-core'

/** 执行一次无需 TTY 的同步检查；只有 `apply` 为 true 时才更新真实分支。 */
export function runMachineSync(options: MachineSyncOptions): MachineSyncResult {
  const worktree = resolveWorktree(options.worktree)
  const initialInspection = inspectWorktree(worktree.path)
  validateWorktree(worktree.record, initialInspection)

  const target = resolveTarget(worktree.path, options.target)
  fetchRemote(worktree.path, target.remote)
  target.oid = resolveRemoteRef(worktree.path, target.ref)

  const inspection = inspectWorktree(worktree.path)
  validateWorktree(worktree.record, inspection)
  if (inspection.head !== initialInspection.head) {
    throw new Error('Worktree HEAD changed while fetching the target; rerun gwt-sync')
  }

  const relation = inspectRelation(worktree.path, target.oid)
  const base = createResultBase(options, worktree.path, inspection, target, relation)

  if (relation.relation === 'equal') {
    return {
      ...base,
      ok: true,
      outcome: 'up-to-date',
      message: `${inspection.branch} already matches ${target.ref}`,
      strategy: strategyResult(options.strategy),
      preflight: null,
      update: notAttemptedUpdate(),
    }
  }

  if (relation.relation === 'ahead') {
    return {
      ...base,
      ok: true,
      outcome: 'ahead',
      message: `${inspection.branch} already contains ${target.ref}`,
      strategy: strategyResult(options.strategy),
      preflight: null,
      update: notAttemptedUpdate(),
    }
  }

  const strategy = resolveStrategy(relation, options.strategy)
  if (!strategy.ok) {
    return {
      ...base,
      ok: false,
      outcome: 'blocked',
      message: strategy.message,
      strategy: strategyResult(options.strategy),
      preflight: null,
      update: notAttemptedUpdate(),
    }
  }

  const snapshots = createWorktreeSnapshots(worktree.path)
  const preflight = preflightUpdate({
    worktree: worktree.path,
    target: target.oid,
    strategy: strategy.value,
    snapshots,
  })
  const strategyInfo = strategyResult(options.strategy, strategy.value)

  if (!preflight.ok) {
    const conflicts = {
      files: preflight.conflictFiles ?? [],
      diff: preflight.conflictDiff ?? null,
    }
    const preflightInfo: MachinePreflight = {
      ok: false,
      allowAttempt: preflight.allowAttempt,
      details: preflight.details,
      conflicts,
    }

    if (!preflight.allowAttempt) {
      return {
        ...base,
        ok: false,
        outcome: 'blocked',
        message: preflight.details,
        strategy: strategyInfo,
        preflight: preflightInfo,
        update: notAttemptedUpdate(),
      }
    }

    if (!options.apply || !options.allowConflicts) {
      return {
        ...base,
        ok: false,
        outcome: 'conflict',
        message: options.apply
          ? 'Conflict detected; rerun with --apply --allow-conflicts to attempt the update'
          : 'Conflict detected; worktree, index, and branch were not updated',
        strategy: strategyInfo,
        preflight: preflightInfo,
        update: notAttemptedUpdate(),
      }
    }

    const update = executeUpdate({
      worktree: worktree.path,
      sourceHead: snapshots.head,
      sourceIndexTree: snapshots.indexTree,
      sourceWorktreeTree: snapshots.fullTree,
      target: target.oid,
      targetLabel: target.ref,
      strategy: strategy.value,
      branch: inspection.branch!,
      status: inspection.status,
      protectDirty: inspection.status.dirty,
      stdio: 'capture',
    })
    return updateResult(base, strategyInfo, preflightInfo, worktree.path, update)
  }

  const preflightInfo: MachinePreflight = {
    ok: true,
    allowAttempt: true,
    details: preflight.details,
    conflicts: { files: [], diff: null },
  }
  if (!options.apply) {
    return {
      ...base,
      ok: true,
      outcome: 'ready',
      message: `Ready to update ${inspection.branch} from ${target.ref}`,
      strategy: strategyInfo,
      preflight: preflightInfo,
      update: notAttemptedUpdate(),
    }
  }

  const update = executeUpdate({
    worktree: worktree.path,
    sourceHead: snapshots.head,
    sourceIndexTree: snapshots.indexTree,
    sourceWorktreeTree: snapshots.fullTree,
    target: target.oid,
    targetLabel: target.ref,
    strategy: strategy.value,
    branch: inspection.branch!,
    status: inspection.status,
    protectDirty: inspection.status.dirty,
    expectedIndexTree: preflight.expectedIndexTree,
    expectedWorktreeTree: preflight.expectedWorktreeTree,
    stdio: 'capture',
  })
  return updateResult(base, strategyInfo, preflightInfo, worktree.path, update)
}

/** 将机器模式结论映射为适合 shell 和 AI 调用方分流的稳定退出码。 */
export function machineExitCode(result: MachineSyncResult): number {
  switch (result.outcome) {
    case 'conflict':
      return 2
    case 'blocked':
      return 3
    case 'failed':
      return 4
    default:
      return 0
  }
}

function resolveWorktree(input: string): ResolvedWorktree {
  const candidate = resolve(input)
  if (!existsSync(candidate) || !statSync(candidate).isDirectory()) {
    throw new Error(`Worktree directory does not exist: ${candidate}`)
  }

  const root = gitText(candidate, ['rev-parse', '--show-toplevel']).trim()
  const record = listWorktrees(root).find((item) => resolve(item.path) === resolve(root))
  if (!record) throw new Error(`Not a registered Git worktree: ${root}`)
  return { path: root, record }
}

function validateWorktree(
  record: WorktreeRecord,
  inspection: WorktreeInspection,
): asserts inspection is WorktreeInspection & { branch: string } {
  if (record.bare) throw new Error('Cannot update a bare worktree')
  if (record.prunable) throw new Error(`Worktree is prunable: ${record.prunable}`)
  if (record.locked) throw new Error(`Worktree is locked: ${record.locked}`)
  if (record.detached || !inspection.branch) throw new Error('Cannot update a detached HEAD worktree')
  if (record.branch && inspection.branch !== record.branch) {
    throw new Error(`Worktree branch changed from ${record.branch} to ${inspection.branch}`)
  }
  if (inspection.operation) {
    throw new Error(`Worktree has an active ${inspection.operation}; finish or abort it first`)
  }
}

function resolveTarget(worktree: string, ref: string): MachineTarget {
  const remotes = gitText(worktree, ['remote'])
    .split(/\r?\n/)
    .map((remote) => remote.trim())
    .filter(Boolean)
    .sort((a, b) => b.length - a.length)
  const remote = remotes.find((name) => ref.startsWith(`${name}/`))
  if (!remote) {
    throw new Error(`Target must name a configured remote branch, for example origin/master: ${ref}`)
  }

  const branch = ref.slice(remote.length + 1)
  if (!branch || branch === 'HEAD') {
    throw new Error(`Target must name an explicit remote branch, not ${ref}`)
  }
  const check = gitRaw(worktree, ['check-ref-format', `refs/remotes/${ref}`])
  if (check.exitCode !== 0) throw new Error(`Invalid remote branch target: ${ref}`)

  return { ref, remote, branch, oid: '' }
}

function fetchRemote(worktree: string, remote: string): void {
  const result = gitRaw(worktree, ['fetch', '--', remote], true)
  if (result.exitCode !== 0) {
    throw new Error(
      [
        `git fetch ${remote} failed (exit ${result.exitCode})`,
        result.stderr,
        result.stdout,
      ].filter(Boolean).join('\n'),
    )
  }
}

function resolveRemoteRef(worktree: string, target: string): string {
  const ref = `refs/remotes/${target}`
  const result = gitRaw(worktree, ['rev-parse', '--verify', `${ref}^{commit}`])
  if (result.exitCode !== 0) {
    throw new Error(`Remote branch does not exist after fetch: ${target}`)
  }
  return result.stdout.trim()
}

function resolveStrategy(
  relation: RelationInspection,
  requested?: UpdateStrategy,
): StrategyResolution {
  if (relation.relation === 'behind') return { ok: true, value: 'ff-only' }
  if (!requested) {
    return {
      ok: false,
      message: 'Diverged branches require --strategy merge or --strategy rebase',
    }
  }
  if (requested === 'ff-only') {
    return {
      ok: false,
      message: 'Diverged branches cannot use --strategy ff-only; choose merge or rebase',
    }
  }
  return { ok: true, value: requested }
}

function createResultBase(
  options: MachineSyncOptions,
  worktree: string,
  inspection: WorktreeInspection & { branch: string },
  target: MachineTarget,
  relation: RelationInspection,
): MachineResultBase {
  return {
    schemaVersion: 1,
    mode: options.apply ? 'apply' : 'inspect',
    worktree: {
      path: worktree,
      branch: inspection.branch,
      head: inspection.head,
      dirty: inspection.status.dirty,
      status: {
        staged: inspection.status.staged,
        unstaged: inspection.status.unstaged,
        untracked: inspection.status.untracked,
        changes: parseStatusChanges(inspection.status.raw),
      },
    },
    target,
    relation,
  }
}

function strategyResult(
  requested?: UpdateStrategy,
  effective: UpdateStrategy | null = null,
): MachineStrategy {
  return { requested: requested ?? null, effective }
}

function parseStatusChanges(raw: string): MachineStatusChange[] {
  const changes: MachineStatusChange[] = []
  const entries = raw.split('\0')

  for (let index = 0; index < entries.length; index++) {
    const entry = entries[index]
    if (!entry) continue
    const indexStatus = entry[0] ?? ' '
    const worktreeStatus = entry[1] ?? ' '
    const change: MachineStatusChange = {
      path: entry.slice(3),
      index: indexStatus,
      worktree: worktreeStatus,
    }
    if (
      indexStatus === 'R'
      || indexStatus === 'C'
      || worktreeStatus === 'R'
      || worktreeStatus === 'C'
    ) {
      change.originalPath = entries[++index]
    }
    changes.push(change)
  }
  return changes
}

function updateResult(
  base: MachineResultBase,
  strategy: MachineStrategy,
  preflight: MachinePreflight,
  worktree: string,
  update: ReturnType<typeof executeUpdate>,
): MachineSyncResult {
  if (update.ok) {
    const finalInspection = inspectWorktree(worktree)
    return {
      ...base,
      ok: true,
      outcome: 'updated',
      message: update.details,
      strategy,
      preflight,
      update: {
        attempted: true,
        applied: true,
        details: update.details,
        head: finalInspection.head,
      },
    }
  }

  return {
    ...base,
    ok: false,
    outcome: 'failed',
    message: update.details,
    strategy,
    preflight,
    update: {
      attempted: true,
      applied: false,
      stage: update.stage,
      details: update.details,
      backupRef: update.backupRef ?? null,
      stashOid: update.stashOid ?? null,
    },
    recovery: createRecovery(worktree, update),
  }
}

function createRecovery(
  worktree: string,
  failure: ExecuteUpdateFailure,
): MachineRecovery {
  let operation: WorktreeInspection['operation']
  try {
    operation = inspectWorktree(worktree).operation
  }
  catch {
    operation = undefined
  }

  const commands: MachineRecoveryCommand[] = []
  for (const action of planRecovery(failure, operation)) {
    switch (action) {
      case 'inspect-status':
        commands.push(command(action, worktree, ['status']))
        break
      case 'inspect-diff':
        commands.push(command(action, worktree, ['diff']))
        commands.push(command(action, worktree, ['diff', '--cached']))
        break
      case 'inspect-stash':
        commands.push(command(action, worktree, ['stash', 'list']))
        if (failure.stashOid) {
          commands.push(command(action, worktree, ['stash', 'show', '--stat', failure.stashOid]))
        }
        break
      case 'inspect-backup':
        if (failure.backupRef) {
          commands.push(command(action, worktree, [
            'log',
            '--oneline',
            '--decorate',
            failure.backupRef,
            '-10',
          ]))
        }
        break
      case 'abort-rebase':
        commands.push(command(action, worktree, ['rebase', '--abort']))
        break
      case 'abort-merge':
        commands.push(command(action, worktree, ['merge', '--abort']))
        break
    }
  }
  return { commands }
}

function command(
  action: MachineRecoveryCommand['action'],
  worktree: string,
  args: string[],
): MachineRecoveryCommand {
  return { action, argv: ['git', '-C', worktree, ...args] }
}

function notAttemptedUpdate(): MachineUpdate {
  return { attempted: false, applied: false }
}

function gitText(cwd: string, args: string[]): string {
  const result = gitRaw(cwd, args)
  if (result.exitCode !== 0) {
    throw new Error(
      [
        `git ${args.join(' ')} failed (exit ${result.exitCode})`,
        result.stderr,
        result.stdout,
      ].filter(Boolean).join('\n'),
    )
  }
  return result.stdout
}

function gitRaw(cwd: string, args: string[], disablePrompt = false): GitResult {
  const result = Bun.spawnSync(['git', '-C', cwd, ...args], {
    stdin: 'ignore',
    stdout: 'pipe',
    stderr: 'pipe',
    env: disablePrompt
      ? { ...process.env, GIT_TERMINAL_PROMPT: '0' }
      : process.env,
  })
  return {
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  }
}

/** 机器模式的声明式参数；默认只预检，不更新真实分支。 */
export interface MachineSyncOptions {
  worktree: string
  target: string
  strategy?: UpdateStrategy
  /**
   * 是否执行已经预检的更新
   *
   * @default false
   */
  apply: boolean
  /**
   * 是否允许尝试已知会产生普通 Git 冲突的更新
   *
   * @default false
   */
  allowConflicts: boolean
}

/** 机器模式可供调用方稳定分流的结论。 */
export type MachineSyncOutcome =
  | 'ready'
  | 'up-to-date'
  | 'ahead'
  | 'conflict'
  | 'blocked'
  | 'updated'
  | 'failed'

/** stdout JSON 的完整生产结果。 */
export interface MachineSyncResult extends MachineResultBase {
  ok: boolean
  outcome: MachineSyncOutcome
  message: string
  strategy: MachineStrategy
  preflight: MachinePreflight | null
  update: MachineUpdate
  recovery?: MachineRecovery
}

interface MachineResultBase {
  schemaVersion: 1
  mode: 'inspect' | 'apply'
  worktree: MachineWorktree
  target: MachineTarget
  relation: RelationInspection
}

interface MachineWorktree {
  path: string
  branch: string
  head: string
  dirty: boolean
  status: {
    staged: number
    unstaged: number
    untracked: number
    changes: MachineStatusChange[]
  }
}

interface MachineStatusChange {
  path: string
  index: string
  worktree: string
  originalPath?: string
}

interface MachineTarget {
  ref: string
  remote: string
  branch: string
  oid: string
}

interface MachineStrategy {
  requested: UpdateStrategy | null
  effective: UpdateStrategy | null
}

interface MachinePreflight {
  ok: boolean
  allowAttempt: boolean
  details: string
  conflicts: {
    files: string[]
    diff: string | null
  }
}

type MachineUpdate =
  | {
    attempted: false
    applied: false
  }
  | {
    attempted: true
    applied: true
    details: string
    head: string
  }
  | {
    attempted: true
    applied: false
    stage: ExecuteUpdateFailure['stage']
    details: string
    backupRef: string | null
    stashOid: string | null
  }

interface MachineRecovery {
  commands: MachineRecoveryCommand[]
}

interface MachineRecoveryCommand {
  action: ReturnType<typeof planRecovery>[number]
  argv: string[]
}

type StrategyResolution =
  | { ok: true; value: UpdateStrategy }
  | { ok: false; message: string }

interface ResolvedWorktree {
  path: string
  record: WorktreeRecord
}

interface GitResult {
  exitCode: number
  stdout: string
  stderr: string
}
