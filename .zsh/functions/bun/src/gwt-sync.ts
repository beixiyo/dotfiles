#!/usr/bin/env bun

/**
 * `gwt-sync` 命令入口：默认通过 fzf 交互选择同步目标，传入 `--json` 时
 * 改用无需 TTY 的机器模式，并把唯一结果写到 stdout
 */

import { existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { parseArgs } from 'node:util'
import { assertCmd, FUNC_DIR, fzf, shellQuote, spawnFzfCapture } from './fzf-shared'
import {
  createWorktreeSnapshots,
  executeUpdate,
  type ExecuteUpdateFailure,
  inspectRelation,
  inspectWorktree,
  listWorktrees,
  planRecovery,
  preflightUpdate,
  type UpdateStrategy,
  type WorktreeInspection,
  type WorktreeRecord,
} from './gwt-sync-core'
import { machineExitCode, type MachineSyncOptions, runMachineSync } from './gwt-sync-machine'
import { C, log, logErr, logOk, logWarn } from './utils'

async function main(argv: string[]): Promise<void> {
  const parsed = parseCliArgs(argv)
  if (parsed.values.help) {
    process.stdout.write(`${usage()}\n`)
    return
  }

  if (parsed.values.json) {
    if (!Bun.which('git')) throw new Error('git is required but not installed')
    const result = runMachineSync(resolveMachineOptions(parsed))
    writeJson(result)
    process.exitCode = machineExitCode(result)
    return
  }

  rejectMachineOptions(parsed)
  assertCmd('git')
  assertCmd('fzf')

  const repository = resolveRepository(parsed.positionals)
  const candidates = collectWorktreeChoices(repository)
  const selected = await selectWorktree(candidates)
  if (!selected) return

  const { record, inspection: selectedInspection } = selected
  validateSelectedWorktree(record, selectedInspection)

  const remote = await selectRemote(record.path)
  if (!remote) return

  log(`Fetching latest refs from ${remote}`)
  if (gitInherited(record.path, ['fetch', remote]) !== 0) {
    throw new Error(`git fetch ${remote} failed`)
  }

  const target = await selectTarget(record.path, remote)
  if (!target) return

  let inspection = inspectWorktree(record.path)
  validateSelectedWorktree(record, inspection)

  let relation: ReturnType<typeof inspectRelation>
  let strategy: UpdateStrategy | undefined
  while (true) {
    const relationHead = inspection.head
    relation = inspectRelation(record.path, target.oid)

    const relationInspection = inspectWorktree(record.path)
    validateSelectedWorktree(record, relationInspection)
    if (relationInspection.head !== relationHead) {
      logWarn('The selected worktree HEAD changed during interaction; recalculating branch relation')
      inspection = relationInspection
      continue
    }
    inspection = relationInspection

    if (relation.relation === 'equal') {
      logOk(`${inspection.branch} is already up to date with ${target.ref}`)
      return
    }
    if (relation.relation === 'ahead') {
      logOk(`${inspection.branch} already contains ${target.ref}; nothing to update`)
      return
    }

    strategy = relation.relation === 'behind'
      ? 'ff-only'
      : await selectStrategy(record.path)
    if (!strategy) return

    const strategyInspection = inspectWorktree(record.path)
    validateSelectedWorktree(record, strategyInspection)
    if (strategyInspection.head !== relationHead) {
      logWarn('The selected worktree HEAD changed during strategy selection; recalculating branch relation')
      inspection = strategyInspection
      continue
    }
    inspection = strategyInspection
    break
  }

  if (!strategy) return

  printSummary({
    worktree: record.path,
    branch: inspection.branch!,
    target: target.ref,
    targetOid: target.oid,
    ahead: relation.ahead,
    behind: relation.behind,
    strategy,
    inspection,
  })

  log('Creating staged and full-worktree snapshots')
  const snapshots = createWorktreeSnapshots(record.path)
  log(`Checking ${strategy} for conflicts`)
  const preflight = preflightUpdate({
    worktree: record.path,
    target: target.oid,
    strategy,
    snapshots,
  })

  const hasPreflightConflict = !preflight.ok
  if (hasPreflightConflict) {
    const message = preflight.allowAttempt
      ? 'Preflight detected a Git conflict; branch, index, and worktree are unchanged'
      : 'Safety preflight failed; branch, index, and worktree are unchanged'
    logWarn(message)
    process.stderr.write(`${preflight.details}\n`)

    if (!preflight.allowAttempt) {
      process.exitCode = 1
      return
    }
  }
  else {
    logOk('Preflight passed')
  }

  if (
    !await confirmExecution({
      branch: inspection.branch!,
      target: target.ref,
      strategy,
      dirty: inspection.status.dirty,
      hasPreflightConflict,
      conflictFiles: preflight.ok ? [] : preflight.conflictFiles ?? [],
      conflictPreview: preflight.ok
        ? undefined
        : preflight.conflictDiff ?? preflight.details,
    })
  ) {
    log('Cancelled; branch was not updated')
    return
  }

  const result = executeUpdate({
    worktree: record.path,
    sourceHead: snapshots.head,
    sourceIndexTree: snapshots.indexTree,
    sourceWorktreeTree: snapshots.fullTree,
    target: target.oid,
    targetLabel: target.ref,
    strategy,
    branch: inspection.branch!,
    status: inspection.status,
    protectDirty: inspection.status.dirty,
    expectedIndexTree: preflight.ok ? preflight.expectedIndexTree : undefined,
    expectedWorktreeTree: preflight.ok ? preflight.expectedWorktreeTree : undefined,
  })

  if (!result.ok) {
    logErr(result.details)
    printRecovery(record.path, result)
    process.exitCode = 1
    return
  }

  logOk(result.details)
  gitInherited(record.path, ['status', '--short', '--branch'])
}

function parseCliArgs(argv: string[]) {
  return parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      worktree: { type: 'string' },
      target: { type: 'string' },
      strategy: { type: 'string' },
      apply: { type: 'boolean' },
      'allow-conflicts': { type: 'boolean' },
      json: { type: 'boolean' },
      help: { type: 'boolean', short: 'h' },
    },
  })
}

function resolveMachineOptions(parsed: ParsedCliArgs): MachineSyncOptions {
  if (parsed.positionals.length > 1) throw new Error(usage())
  if (parsed.values.worktree && parsed.positionals.length > 0) {
    throw new Error('Pass the worktree either as --worktree or as one positional path, not both')
  }

  const target = parsed.values.target
  if (!target) throw new Error('--target must name a remote branch such as origin/master')

  const strategyValue = parsed.values.strategy
  let strategy: UpdateStrategy | undefined
  if (strategyValue) {
    if (!isUpdateStrategy(strategyValue)) {
      throw new Error(`Unknown strategy: ${strategyValue}; expected ff-only, merge, or rebase`)
    }
    strategy = strategyValue
  }

  const apply = parsed.values.apply === true
  const allowConflicts = parsed.values['allow-conflicts'] === true
  if (allowConflicts && !apply) {
    throw new Error('--allow-conflicts requires --apply')
  }

  return {
    worktree: parsed.values.worktree ?? parsed.positionals[0] ?? '.',
    target,
    strategy,
    apply,
    allowConflicts,
  }
}

function rejectMachineOptions(parsed: ParsedCliArgs): void {
  if (
    parsed.values.worktree
    || parsed.values.target
    || parsed.values.strategy
    || parsed.values.apply
    || parsed.values['allow-conflicts']
  ) {
    throw new Error('Machine options require --json; --json itself disables all interactive UI')
  }
  if (parsed.positionals.length > 1) throw new Error(usage())
}

function isUpdateStrategy(value: string): value is UpdateStrategy {
  return value === 'ff-only' || value === 'merge' || value === 'rebase'
}

function usage(): string {
  return [
    'Usage:',
    '  gwt-sync [repository-path]',
    '  gwt-sync --json [--worktree path] --target remote/branch [--strategy merge|rebase] [--apply] [--allow-conflicts]',
    '',
    'Machine mode fetches the target remote and inspects by default; --apply updates the branch.',
    'Known conflicts still require --apply --allow-conflicts before a real update is attempted.',
  ].join('\n')
}

function writeJson(value: unknown): void {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`)
}

function resolveRepository(argv: string[]): string {
  const positional = argv.filter((argument) => !argument.startsWith('-'))
  const candidate = resolve(positional[0] ?? '.')
  if (!existsSync(candidate) || !statSync(candidate).isDirectory()) {
    throw new Error(`Directory does not exist: ${candidate}`)
  }

  const result = gitRaw(candidate, ['rev-parse', '--show-toplevel'])
  if (result.exitCode !== 0) throw new Error(`Not a Git repository: ${candidate}`)
  return result.stdout.trim()
}

function collectWorktreeChoices(repository: string): WorktreeChoice[] {
  return listWorktrees(repository).map((record) => {
    if (record.bare || record.prunable || !existsSync(record.path)) {
      return { record }
    }

    try {
      return { record, inspection: inspectWorktree(record.path) }
    }
    catch (error) {
      return {
        record,
        error: error instanceof Error ? error.message : String(error),
      }
    }
  })
}

async function selectWorktree(choices: WorktreeChoice[]): Promise<WorktreeChoice | undefined> {
  const rows = choices.map(({ record, inspection, error }) => {
    const branch = record.detached
      ? '(detached)'
      : record.branch ?? '(no branch)'
    const state = record.prunable
      ? 'prunable'
      : record.locked
      ? 'locked'
      : error
      ? 'error'
      : inspection?.status.dirty
      ? `dirty ${formatStatus(inspection)}`
      : 'clean'

    return [
      record.path,
      state,
      branch,
      record.head.slice(0, 10),
    ].join('\t')
  })

  const [, output] = await spawnFzfCapture([
    '--ansi',
    '--delimiter',
    '\t',
    '--with-nth=2..',
    '--no-multi',
    '--header',
    [
      'Select a worktree to update',
      `Navigate ${fzf.cmdHint}n/${fzf.cmdHint}p │ Scroll ^e/^y │ Cancel Esc`,
    ].join('\n'),
    '--header-first',
    '--prompt',
    'Worktree > ',
    '--preview',
    `${FUNC_DIR}/_preview/git-worktree-sync.sh {1}`,
    '--preview-window',
    fzf.gitPreviewWindow,
    '--bind',
    fzf.scrollBinds,
  ], rows.join('\n'))

  if (!output) return undefined
  const path = output.split('\t')[0]
  return choices.find((choice) => choice.record.path === path)
}

function validateSelectedWorktree(
  record: WorktreeRecord,
  inspection?: WorktreeInspection,
): asserts inspection is WorktreeInspection {
  if (record.bare) throw new Error('Cannot update a bare worktree')
  if (record.prunable) throw new Error(`Worktree is prunable: ${record.prunable}`)
  if (record.locked) throw new Error(`Worktree is locked: ${record.locked}`)
  if (!inspection) throw new Error('Unable to inspect the selected worktree')
  if (record.detached || !inspection.branch) throw new Error('Cannot update a detached HEAD worktree')
  if (record.branch && inspection.branch !== record.branch) {
    throw new Error(`Worktree branch changed from ${record.branch} to ${inspection.branch}`)
  }
  if (inspection.operation) {
    throw new Error(`Worktree has an active ${inspection.operation}; finish or abort it first`)
  }
}

async function selectRemote(worktree: string): Promise<string | undefined> {
  const names = gitText(worktree, ['remote'])
    .split(/\r?\n/)
    .map((name) => name.trim())
    .filter(Boolean)
  if (names.length === 0) throw new Error('Repository has no configured remotes')
  if (names.length === 1) return names[0]

  const rows = names.map((name) => {
    const url = gitRaw(worktree, ['remote', 'get-url', name]).stdout.trim()
    return `${name}\t${url}`
  })
  const selected = await selectRow(rows, {
    header: 'Select a remote to fetch',
    prompt: 'Remote > ',
    withNth: '1,2',
  })
  return selected?.split('\t')[0]
}

async function selectTarget(worktree: string, remote: string): Promise<TargetChoice | undefined> {
  const format = '%(refname:short)%09%(objectname)%09%(objectname:short)%09%(subject)'
  const raw = gitText(worktree, [
    'for-each-ref',
    `--format=${format}`,
    `refs/remotes/${remote}`,
  ])
  const symbolicHead = gitRaw(worktree, [
    'symbolic-ref',
    '--quiet',
    '--short',
    `refs/remotes/${remote}/HEAD`,
  ]).stdout.trim()

  const targets = raw
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      const [ref, oid, shortOid, ...subjectParts] = line.split('\t')
      return { ref, oid, shortOid, subject: subjectParts.join('\t') }
    })
    .filter((target) => target.ref !== remote && target.ref !== `${remote}/HEAD`)

  if (targets.length === 0) throw new Error(`${remote} has no available remote branches`)

  targets.sort((a, b) => {
    if (a.ref === symbolicHead) return -1
    if (b.ref === symbolicHead) return 1
    return a.ref.localeCompare(b.ref, 'en')
  })

  const rows = targets.map((target) =>
    [
      target.ref,
      target.oid,
      target.shortOid,
      target.subject,
    ].join('\t')
  )
  const selected = await selectRow(rows, {
    header: symbolicHead
      ? `Select a target branch (remote default: ${symbolicHead})`
      : 'Select a target branch',
    prompt: 'Target > ',
    withNth: '1,3,4',
    preview: `git -C ${shellQuote(worktree)} --no-pager log --oneline --decorate --color=always -20 {1}`,
  })
  if (!selected) return undefined

  const [ref, oid, shortOid, ...subjectParts] = selected.split('\t')
  return { ref, oid, shortOid, subject: subjectParts.join('\t') }
}

async function selectStrategy(worktree: string): Promise<UpdateStrategy | undefined> {
  const hasUpstream = gitRaw(worktree, [
    'rev-parse',
    '--abbrev-ref',
    '--symbolic-full-name',
    '@{upstream}',
  ]).exitCode === 0
  const rows = hasUpstream
    ? [
      'merge\tMerge: preserve history; suitable for a shared branch',
      'rebase\tRebase: linearize history and rewrite branch-only commits',
    ]
    : [
      'rebase\tRebase: linearize history; suitable for an unshared feature branch',
      'merge\tMerge: preserve history and create a merge commit',
    ]
  const selected = await selectRow(rows, {
    header: 'The current branch has diverged from the target; select an update strategy',
    prompt: 'Strategy > ',
    withNth: '2',
  })
  return selected?.split('\t')[0] as UpdateStrategy | undefined
}

async function confirmExecution(summary: ConfirmationSummary): Promise<boolean> {
  const dirtyText = summary.dirty
    ? 'Local changes will be stashed and restored'
    : 'Worktree is clean'
  const conflictText = formatConflictFiles(summary.conflictFiles)
  const rows = summary.hasPreflightConflict
    ? [
      'cancel\tCancel and keep the current state (recommended)',
      'execute\tAttempt the update; manual conflict resolution may be required',
    ]
    : [
      'execute\tRun the update (default)',
      'cancel\tCancel without updating the branch',
    ]
  let previewRoot: string | undefined

  try {
    let preview: string | undefined
    if (summary.hasPreflightConflict && summary.conflictPreview) {
      previewRoot = mkdtempSync(join(tmpdir(), 'gwt-sync-conflict-'))
      const report = join(previewRoot, 'conflict.diff')
      writeFileSync(report, summary.conflictPreview)
      preview = `${FUNC_DIR}/_preview/git-worktree-sync-conflict.sh ${shellQuote(report)}`
    }

    const selected = await selectRow(rows, {
      header: [
        `${summary.branch} ← ${summary.target}`,
        `${summary.strategy} │ ${dirtyText}`,
        summary.hasPreflightConflict
          ? conflictText
          : 'No conflicts detected; press Enter to run',
        summary.hasPreflightConflict
          ? `Review preview ^e/^y │ Continue only if manual resolution is acceptable`
          : '',
      ].filter(Boolean).join('\n'),
      prompt: 'Confirm > ',
      withNth: '2',
      preview,
    })
    return selected?.startsWith('execute\t') ?? false
  }
  finally {
    if (previewRoot) rmSync(previewRoot, { recursive: true, force: true })
  }
}

function formatConflictFiles(files: string[]): string {
  if (files.length === 0) return 'Conflict detected; no individual path was reported'

  const visible = files.slice(0, 3).map((file) => (
    file
      .replaceAll('\\', '\\\\')
      .replaceAll('\r', '\\r')
      .replaceAll('\n', '\\n')
      .replaceAll('\t', '\\t')
  ))
  const remaining = files.length - visible.length
  return [
    `Conflicts (${files.length}): ${visible.join(', ')}`,
    remaining > 0 ? `+${remaining} more in preview` : '',
  ].filter(Boolean).join(' ')
}

async function selectRow(rows: string[], options: SelectRowOptions): Promise<string | undefined> {
  const args = [
    '--ansi',
    '--delimiter',
    '\t',
    '--with-nth',
    options.withNth,
    '--no-multi',
    '--no-sort',
    '--header',
    options.header,
    '--header-first',
    '--prompt',
    options.prompt,
    '--bind',
    fzf.scrollBinds,
  ]
  if (options.preview) {
    args.push('--preview', options.preview, '--preview-window', fzf.gitPreviewWindow)
  }

  const [, selected] = await spawnFzfCapture(args, rows.join('\n'))
  return selected || undefined
}

function printSummary(summary: UpdateSummary): void {
  const dirty = summary.inspection.status.dirty
    ? formatStatus(summary.inspection)
    : 'clean'
  process.stderr.write([
    '',
    `${C.bold}Worktree${C.reset}  ${summary.worktree}`,
    `${C.bold}Branch${C.reset}    ${summary.branch}`,
    `${C.bold}Target${C.reset}    ${summary.target} (${summary.targetOid.slice(0, 12)})`,
    `${C.bold}Relation${C.reset}  ahead ${summary.ahead} / behind ${summary.behind}`,
    `${C.bold}Strategy${C.reset}  ${summary.strategy}`,
    `${C.bold}Status${C.reset}    ${dirty}`,
    '',
  ].join('\n'))
}

function formatStatus(inspection: WorktreeInspection): string {
  const { staged, unstaged, untracked } = inspection.status
  return `staged ${staged}, unstaged ${unstaged}, untracked ${untracked}`
}

function printRecovery(
  worktree: string,
  failure: ExecuteUpdateFailure,
): void {
  const cwd = shellQuote(worktree)
  let operation: ReturnType<typeof inspectWorktree>['operation']
  try {
    operation = inspectWorktree(worktree).operation
  }
  catch {
    operation = undefined
  }

  logWarn(`Sync stopped during ${failure.stage}; the recovery steps below will not reapply the stash:`)
  for (const action of planRecovery(failure, operation)) {
    switch (action) {
      case 'inspect-status':
        process.stderr.write(`git -C ${cwd} status\n`)
        break
      case 'inspect-diff':
        process.stderr.write(`git -C ${cwd} diff\n`)
        process.stderr.write(`git -C ${cwd} diff --cached\n`)
        break
      case 'inspect-stash':
        process.stderr.write(`git -C ${cwd} stash list\n`)
        if (failure.stashOid) {
          process.stderr.write(`git -C ${cwd} stash show --stat ${failure.stashOid}\n`)
        }
        break
      case 'inspect-backup':
        if (failure.backupRef) {
          process.stderr.write(`git -C ${cwd} log --oneline --decorate ${shellQuote(failure.backupRef)} -10\n`)
        }
        break
      case 'abort-rebase':
        process.stderr.write(`git -C ${cwd} rebase --abort\n`)
        break
      case 'abort-merge':
        process.stderr.write(`git -C ${cwd} merge --abort\n`)
        break
    }
  }
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

function gitRaw(cwd: string, args: string[]): GitResult {
  const result = Bun.spawnSync(['git', '-C', cwd, ...args], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  return {
    exitCode: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  }
}

function gitInherited(cwd: string, args: string[]): number {
  return Bun.spawnSync(['git', '-C', cwd, ...args], {
    stdin: 'inherit',
    stdout: 'inherit',
    stderr: 'inherit',
  }).exitCode
}

const argv = process.argv.slice(2)
main(argv).catch((error) => {
  const message = error instanceof Error ? error.message : String(error)
  if (argv.includes('--json')) {
    writeJson({
      schemaVersion: 1,
      ok: false,
      mode: argv.includes('--apply') ? 'apply' : 'inspect',
      outcome: 'error',
      error: { message },
    })
  }
  else {
    logErr(message)
  }
  process.exitCode = 1
})

type ParsedCliArgs = ReturnType<typeof parseCliArgs>

interface WorktreeChoice {
  record: WorktreeRecord
  inspection?: WorktreeInspection
  error?: string
}

interface TargetChoice {
  ref: string
  oid: string
  shortOid: string
  subject: string
}

interface SelectRowOptions {
  header: string
  prompt: string
  withNth: string
  preview?: string
}

interface UpdateSummary {
  worktree: string
  branch: string
  target: string
  targetOid: string
  ahead: number
  behind: number
  strategy: UpdateStrategy
  inspection: WorktreeInspection
}

interface ConfirmationSummary {
  branch: string
  target: string
  strategy: UpdateStrategy
  dirty: boolean
  hasPreflightConflict: boolean
  conflictFiles: string[]
  conflictPreview?: string
}

interface GitResult {
  exitCode: number
  stdout: string
  stderr: string
}
