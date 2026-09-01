/**
 * gwt-sync 高信号集成测试：使用真实临时 Git 仓库验证 dirty 状态恢复、
 * add/add 冲突，以及 merge-tree 无法代表逐提交 rebase 的边界
 */

import { afterEach, describe, expect, it } from 'bun:test'
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  createWorktreeSnapshots,
  executeUpdate,
  findDirtyNestedRepositories,
  findIgnoredPathConflicts,
  inspectRelation,
  inspectWorktree,
  parseWorktreePorcelain,
  planRecovery,
  preflightUpdate,
} from './gwt-sync-core'

const temporaryRepositories: string[] = []

afterEach(() => {
  for (const repository of temporaryRepositories.splice(0)) {
    rmSync(repository, { recursive: true, force: true })
  }
})

describe('gwt-sync', () => {
  it('保留 staged、unstaged 和 untracked 边界后 fast-forward', () => {
    const repository = createRepository()
    write(repository, 'staged.txt', 'base staged\n')
    write(repository, 'unstaged.txt', 'base unstaged\n')
    git(repository, ['add', '.'])
    git(repository, ['commit', '-m', 'base'])
    git(repository, ['branch', 'feature'])

    write(repository, 'main.txt', 'from main\n')
    git(repository, ['add', 'main.txt'])
    git(repository, ['commit', '-m', 'main update'])
    const target = git(repository, ['rev-parse', 'main']).trim()

    git(repository, ['checkout', 'feature'])
    write(repository, 'unstaged.txt', 'existing user stash\n')
    git(repository, ['stash', 'push', '--message', 'USER STASH'])
    const existingStash = git(repository, ['rev-parse', 'refs/stash']).trim()

    write(repository, 'staged.txt', 'staged local change\n')
    git(repository, ['add', 'staged.txt'])
    write(repository, 'unstaged.txt', 'unstaged local change\n')
    write(repository, 'untracked.txt', 'untracked local change\n')

    const before = git(repository, [
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ])
    const inspection = inspectWorktree(repository)
    const relation = inspectRelation(repository, target)
    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'ff-only',
      snapshots,
    })

    expect(relation).toMatchObject({ ahead: 0, behind: 1, relation: 'behind' })
    expect(preflight.ok).toBe(true)

    const result = executeUpdate({
      worktree: repository,
      sourceHead: snapshots.head,
      sourceIndexTree: snapshots.indexTree,
      sourceWorktreeTree: snapshots.fullTree,
      target,
      targetLabel: 'main',
      strategy: 'ff-only',
      branch: 'feature',
      status: inspection.status,
      protectDirty: true,
      expectedIndexTree: preflight.expectedIndexTree!,
      expectedWorktreeTree: preflight.expectedWorktreeTree!,
    })

    expect(result).toEqual({
      ok: true,
      details: 'feature updated to main via ff-only',
    })
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(target)
    expect(git(repository, [
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ])).toBe(before)
    expect(read(repository, 'staged.txt')).toBe('staged local change\n')
    expect(read(repository, 'unstaged.txt')).toBe('unstaged local change\n')
    expect(read(repository, 'untracked.txt')).toBe('untracked local change\n')
    expect(git(repository, ['rev-parse', 'refs/stash']).trim()).toBe(existingStash)
    expect(git(repository, ['stash', 'list'])).toContain('USER STASH')
    expect(git(repository, [
      'for-each-ref',
      '--format=%(refname)',
      'refs/gwt-sync-backup',
    ])).toBe('')
  })

  it('未跟踪文件与目标分支同名新增时阻止更新', () => {
    const repository = createRepository()
    git(repository, ['commit', '--allow-empty', '-m', 'base'])
    git(repository, ['branch', 'feature'])

    write(repository, 'same.txt', 'from main\n')
    git(repository, ['add', 'same.txt'])
    git(repository, ['commit', '-m', 'add same file on main'])
    const target = git(repository, ['rev-parse', 'main']).trim()

    git(repository, ['checkout', 'feature'])
    write(repository, 'same.txt', 'local untracked content\n')
    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'ff-only',
      snapshots,
    })

    expect(preflight.ok).toBe(false)
    if (preflight.ok) throw new Error('Expected an add/add conflict')
    expect(preflight.details).toContain('same.txt')
    expect(preflight.conflictFiles).toEqual(['same.txt'])
    expect(preflight.conflictDiff).toContain('diff --git a/same.txt b/same.txt')
    expect(preflight.conflictDiff).toContain('<<<<<<<')
    expect(git(repository, ['rev-parse', '--abbrev-ref', 'HEAD']).trim()).toBe('feature')
    expect(read(repository, 'same.txt')).toBe('local untracked content\n')
  })

  it('目标路径与 ignored 文件或父子路径碰撞时阻止更新', () => {
    const repository = createRepository()
    write(
      repository,
      '.gitignore',
      [
        'ignored.txt',
        'ignored-parent',
        'container/private.txt',
        '',
      ].join('\n'),
    )
    git(repository, ['add', '.gitignore'])
    git(repository, ['commit', '-m', 'base ignore rules'])
    git(repository, ['branch', 'feature'])

    write(repository, 'ignored.txt', 'target exact\n')
    mkdirSync(join(repository, 'ignored-parent'))
    write(repository, 'ignored-parent/child.txt', 'target child\n')
    write(repository, 'container', 'target replaces directory\n')
    git(repository, ['add', '--force', 'ignored.txt', 'ignored-parent/child.txt', 'container'])
    git(repository, ['commit', '-m', 'target adds collision paths'])
    const target = git(repository, ['rev-parse', 'main']).trim()

    git(repository, ['checkout', 'feature'])
    write(repository, 'ignored.txt', 'LOCAL SECRET\n')
    write(repository, 'ignored-parent', 'LOCAL PARENT FILE\n')
    mkdirSync(join(repository, 'container'))
    write(repository, 'container/private.txt', 'LOCAL PRIVATE\n')

    const conflicts = findIgnoredPathConflicts(repository, target)
    const inspection = inspectWorktree(repository)
    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'ff-only',
      snapshots,
    })

    expect(conflicts).toEqual(expect.arrayContaining([
      {
        targetPath: 'ignored.txt',
        localPath: 'ignored.txt',
        relation: 'same-path',
      },
      {
        targetPath: 'ignored-parent/child.txt',
        localPath: 'ignored-parent',
        relation: 'local-parent',
      },
      {
        targetPath: 'container',
        localPath: 'container/',
        relation: 'local-descendant',
      },
    ]))
    expect(preflight.ok).toBe(false)
    expect(preflight.details).toContain('ignored paths')
    expect(() =>
      executeUpdate({
        worktree: repository,
        sourceHead: snapshots.head,
        sourceIndexTree: snapshots.indexTree,
        sourceWorktreeTree: snapshots.fullTree,
        target,
        targetLabel: 'main',
        strategy: 'ff-only',
        branch: 'feature',
        status: inspection.status,
        protectDirty: false,
        expectedIndexTree: snapshots.indexTree,
        expectedWorktreeTree: snapshots.fullTree,
      })
    ).toThrow('ignored paths')
    expect(read(repository, 'ignored.txt')).toBe('LOCAL SECRET\n')
    expect(read(repository, 'ignored-parent')).toBe('LOCAL PARENT FILE\n')
    expect(read(repository, 'container/private.txt')).toBe('LOCAL PRIVATE\n')
    expect(git(repository, ['rev-parse', '--abbrev-ref', 'HEAD']).trim()).toBe('feature')
  })

  it('rebase 中间提交短暂写入 ignored 路径时阻止更新', () => {
    const repository = createRepository()
    write(repository, '.gitignore', 'transient.txt\n')
    git(repository, ['add', '.gitignore'])
    git(repository, ['commit', '-m', 'base ignore rule'])

    git(repository, ['checkout', '-b', 'feature'])
    write(repository, 'transient.txt', 'feature transient content\n')
    git(repository, ['add', '--force', 'transient.txt'])
    git(repository, ['commit', '-m', 'feature temporarily adds ignored path'])
    git(repository, ['rm', 'transient.txt'])
    git(repository, ['commit', '-m', 'feature removes ignored path'])

    git(repository, ['checkout', 'main'])
    write(repository, 'main.txt', 'unrelated main update\n')
    git(repository, ['add', 'main.txt'])
    git(repository, ['commit', '-m', 'main update'])
    const target = git(repository, ['rev-parse', 'main']).trim()

    git(repository, ['checkout', 'feature'])
    write(repository, 'transient.txt', 'LOCAL SECRET\n')

    const inspection = inspectWorktree(repository)
    const conflicts = findIgnoredPathConflicts(repository, target, {
      strategy: 'rebase',
    })
    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'rebase',
      snapshots,
    })

    expect(inspection.status.dirty).toBe(false)
    expect(conflicts).toContainEqual({
      targetPath: 'transient.txt',
      localPath: 'transient.txt',
      relation: 'same-path',
    })
    expect(preflight.ok).toBe(false)
    expect(preflight.details).toContain('transient.txt')
    expect(() =>
      executeUpdate({
        worktree: repository,
        sourceHead: snapshots.head,
        sourceIndexTree: snapshots.indexTree,
        sourceWorktreeTree: snapshots.fullTree,
        target,
        targetLabel: 'main',
        strategy: 'rebase',
        branch: 'feature',
        status: inspection.status,
        protectDirty: false,
        expectedIndexTree: snapshots.indexTree,
        expectedWorktreeTree: snapshots.fullTree,
      })
    ).toThrow('transient.txt')
    expect(read(repository, 'transient.txt')).toBe('LOCAL SECRET\n')
    expect(git(repository, ['rev-parse', '--abbrev-ref', 'HEAD']).trim()).toBe('feature')
    expect(git(repository, [
      'for-each-ref',
      '--format=%(refname)',
      'refs/gwt-sync-backup',
    ])).toBe('')
  })

  it('rebase 预检不改写重放范围内的其他本地分支', () => {
    const repository = createRepository()
    // 用户为 stacked 分支开启 rebase.updateRefs，预检重放不得借此改写引用
    git(repository, ['config', 'rebase.updateRefs', 'true'])
    write(repository, 'base.txt', 'base\n')
    git(repository, ['add', 'base.txt'])
    git(repository, ['commit', '-m', 'base'])

    git(repository, ['checkout', '-b', 'feature'])
    write(repository, 'feature-1.txt', 'feature 1\n')
    git(repository, ['add', 'feature-1.txt'])
    git(repository, ['commit', '-m', 'feature commit 1'])
    git(repository, ['branch', 'stacked'])
    write(repository, 'feature-2.txt', 'feature 2\n')
    git(repository, ['add', 'feature-2.txt'])
    git(repository, ['commit', '-m', 'feature commit 2'])

    git(repository, ['checkout', 'main'])
    write(repository, 'main.txt', 'main update\n')
    git(repository, ['add', 'main.txt'])
    git(repository, ['commit', '-m', 'main update'])
    const target = git(repository, ['rev-parse', 'main']).trim()

    git(repository, ['checkout', 'feature'])
    write(repository, 'local.txt', 'local change\n')
    git(repository, ['add', 'local.txt'])

    const stackedBefore = git(repository, ['rev-parse', 'stacked']).trim()
    const refsBefore = git(repository, [
      'for-each-ref',
      '--format=%(refname) %(objectname)',
    ])

    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'rebase',
      snapshots,
    })

    expect(preflight.ok).toBe(true)
    expect(git(repository, ['rev-parse', 'stacked']).trim()).toBe(stackedBefore)
    expect(git(repository, [
      'for-each-ref',
      '--format=%(refname) %(objectname)',
    ])).toBe(refsBefore)
  })

  it('rebase 分支仍跟踪被 ignore 规则命中的路径时不误报', () => {
    const repository = createRepository()
    write(repository, '.gitignore', 'generated.txt\n')
    git(repository, ['add', '.gitignore'])
    git(repository, ['commit', '-m', 'base ignore rule'])

    git(repository, ['checkout', '-b', 'feature'])
    write(repository, 'generated.txt', 'tracked generated content\n')
    git(repository, ['add', '--force', 'generated.txt'])
    git(repository, ['commit', '-m', 'feature tracks generated path'])

    git(repository, ['checkout', 'main'])
    write(repository, 'main.txt', 'main update\n')
    git(repository, ['add', 'main.txt'])
    git(repository, ['commit', '-m', 'main update'])
    const target = git(repository, ['rev-parse', 'main']).trim()
    git(repository, ['checkout', 'feature'])

    const inspection = inspectWorktree(repository)
    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'rebase',
      snapshots,
    })

    expect(findIgnoredPathConflicts(repository, target, {
      strategy: 'rebase',
    })).toEqual([])
    expect(preflight.ok).toBe(true)

    const result = executeUpdate({
      worktree: repository,
      sourceHead: snapshots.head,
      sourceIndexTree: snapshots.indexTree,
      sourceWorktreeTree: snapshots.fullTree,
      target,
      targetLabel: 'main',
      strategy: 'rebase',
      branch: 'feature',
      status: inspection.status,
      protectDirty: false,
      expectedIndexTree: preflight.expectedIndexTree!,
      expectedWorktreeTree: preflight.expectedWorktreeTree!,
    })

    expect(result.ok).toBe(true)
    expect(read(repository, 'generated.txt')).toBe('tracked generated content\n')
  })

  it('submodule-only dirty 时阻止更新并保留已有用户 stash', () => {
    const child = createRepository()
    write(child, 'child.txt', 'child base\n')
    git(child, ['add', 'child.txt'])
    git(child, ['commit', '-m', 'child base'])

    const repository = createRepository()
    write(repository, 'sync.txt', 'A\n')
    git(repository, ['add', 'sync.txt'])
    git(repository, [
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      child,
      'child',
    ])
    git(repository, ['commit', '-m', 'super base'])
    expect(findDirtyNestedRepositories(repository)).toEqual([])
    git(repository, ['submodule', 'deinit', '--force', 'child'])
    expect(findDirtyNestedRepositories(repository)).toEqual([])
    git(repository, [
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'update',
      '--init',
      'child',
    ])
    git(repository, ['branch', 'feature'])

    git(repository, ['checkout', 'feature'])
    write(repository, 'sync.txt', 'B\n')
    git(repository, ['stash', 'push', '--message', 'USER STASH'])
    const existingStash = git(repository, ['rev-parse', 'refs/stash']).trim()

    git(repository, ['checkout', 'main'])
    write(repository, 'sync.txt', 'B\n')
    git(repository, ['commit', '-am', 'main update'])
    const target = git(repository, ['rev-parse', 'main']).trim()
    git(repository, ['checkout', 'feature'])

    write(join(repository, 'child'), 'child.txt', 'dirty inside submodule\n')
    const inspection = inspectWorktree(repository)
    const snapshots = createWorktreeSnapshots(repository)
    const nested = findDirtyNestedRepositories(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'ff-only',
      snapshots,
    })

    expect(inspection.status.dirty).toBe(true)
    expect(nested).toEqual(expect.arrayContaining([
      expect.objectContaining({ path: 'child', kind: 'submodule' }),
    ]))
    expect(preflight.ok).toBe(false)
    expect(preflight.details).toContain('submodule')
    expect(() =>
      executeUpdate({
        worktree: repository,
        sourceHead: snapshots.head,
        sourceIndexTree: snapshots.indexTree,
        sourceWorktreeTree: snapshots.fullTree,
        target,
        targetLabel: 'main',
        strategy: 'ff-only',
        branch: 'feature',
        status: inspection.status,
        protectDirty: true,
        expectedIndexTree: snapshots.indexTree,
        expectedWorktreeTree: snapshots.fullTree,
      })
    ).toThrow('submodule')
    expect(git(repository, ['rev-parse', 'refs/stash']).trim()).toBe(existingStash)
    expect(git(repository, ['stash', 'list'])).toContain('USER STASH')
    expect(git(repository, ['rev-parse', '--abbrev-ref', 'HEAD']).trim()).toBe('feature')
    expect(read(join(repository, 'child'), 'child.txt')).toBe('dirty inside submodule\n')
  })

  it('最终树可合并但中间提交冲突时仍阻止 rebase', () => {
    const repository = createRepository()
    write(repository, 'value.txt', 'A\n')
    git(repository, ['add', 'value.txt'])
    git(repository, ['commit', '-m', 'base A'])
    const base = git(repository, ['rev-parse', 'HEAD']).trim()

    git(repository, ['checkout', '-b', 'feature'])
    write(repository, 'value.txt', 'B\n')
    git(repository, ['commit', '-am', 'feature A to B'])
    write(repository, 'value.txt', 'A\n')
    git(repository, ['commit', '-am', 'feature B back to A'])

    git(repository, ['checkout', 'main'])
    write(repository, 'value.txt', 'C\n')
    git(repository, ['commit', '-am', 'main A to C'])
    const target = git(repository, ['rev-parse', 'main']).trim()
    git(repository, ['checkout', 'feature'])
    expect(git(repository, ['merge-base', 'HEAD', target]).trim()).toBe(base)

    const snapshots = createWorktreeSnapshots(repository)
    const mergePreflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'merge',
      snapshots,
    })
    const rebasePreflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'rebase',
      snapshots,
    })

    expect(mergePreflight.ok).toBe(true)
    expect(rebasePreflight.ok).toBe(false)
    expect(rebasePreflight.details).toContain('value.txt')
    expect(git(repository, ['rev-parse', '--abbrev-ref', 'HEAD']).trim()).toBe('feature')
    expect(git(repository, ['status', '--porcelain'])).toBe('')
  })

  it('分叉分支 rebase 后恢复 dirty worktree 的原始边界', () => {
    const repository = createRepository()
    write(repository, 'staged.txt', 'base staged\n')
    write(repository, 'unstaged.txt', 'base unstaged\n')
    git(repository, ['add', '.'])
    git(repository, ['commit', '-m', 'base'])

    git(repository, ['checkout', '-b', 'feature'])
    write(repository, 'feature.txt', 'feature commit\n')
    git(repository, ['add', 'feature.txt'])
    git(repository, ['commit', '-m', 'feature update'])

    git(repository, ['checkout', 'main'])
    write(repository, 'main.txt', 'main commit\n')
    git(repository, ['add', 'main.txt'])
    git(repository, ['commit', '-m', 'main update'])
    const target = git(repository, ['rev-parse', 'main']).trim()

    git(repository, ['checkout', 'feature'])
    write(repository, 'staged.txt', 'staged after feature\n')
    git(repository, ['add', 'staged.txt'])
    write(repository, 'unstaged.txt', 'unstaged after feature\n')
    write(repository, 'untracked.txt', 'untracked after feature\n')

    const before = git(repository, [
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ])
    const inspection = inspectWorktree(repository)
    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'rebase',
      snapshots,
    })

    expect(inspectRelation(repository, target).relation).toBe('diverged')
    expect(preflight.ok).toBe(true)

    const result = executeUpdate({
      worktree: repository,
      sourceHead: snapshots.head,
      sourceIndexTree: snapshots.indexTree,
      sourceWorktreeTree: snapshots.fullTree,
      target,
      targetLabel: 'main',
      strategy: 'rebase',
      branch: 'feature',
      status: inspection.status,
      protectDirty: true,
      expectedIndexTree: preflight.expectedIndexTree!,
      expectedWorktreeTree: preflight.expectedWorktreeTree!,
    })

    expect(result.ok).toBe(true)
    expect(git(repository, ['merge-base', 'HEAD', 'main']).trim()).toBe(target)
    expect(git(repository, ['rev-list', '--count', 'main..HEAD']).trim()).toBe('1')
    expect(git(repository, [
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ])).toBe(before)
  })

  it('预检后 worktree 内容变化时拒绝执行并且不创建恢复状态', () => {
    const repository = createRepository()
    write(repository, 'late-change.txt', 'base\n')
    git(repository, ['add', 'late-change.txt'])
    git(repository, ['commit', '-m', 'base'])
    git(repository, ['branch', 'feature'])
    git(repository, ['commit', '--allow-empty', '-m', 'main update'])
    const target = git(repository, ['rev-parse', 'main']).trim()
    git(repository, ['checkout', 'feature'])

    write(repository, 'late-change.txt', 'content during preflight\n')

    const inspection = inspectWorktree(repository)
    const snapshots = createWorktreeSnapshots(repository)
    const preflight = preflightUpdate({
      worktree: repository,
      target,
      strategy: 'ff-only',
      snapshots,
    })
    expect(preflight.ok).toBe(true)

    write(repository, 'late-change.txt', 'changed after preflight\n')
    expect(inspectWorktree(repository).status.raw).toBe(inspection.status.raw)

    expect(() =>
      executeUpdate({
        worktree: repository,
        sourceHead: snapshots.head,
        sourceIndexTree: snapshots.indexTree,
        sourceWorktreeTree: snapshots.fullTree,
        target,
        targetLabel: 'main',
        strategy: 'ff-only',
        branch: 'feature',
        status: inspection.status,
        protectDirty: true,
        expectedIndexTree: preflight.expectedIndexTree!,
        expectedWorktreeTree: preflight.expectedWorktreeTree!,
      })
    ).toThrow('Worktree content changed after preflight')
    expect(git(repository, ['stash', 'list'])).toBe('')
    expect(git(repository, [
      'for-each-ref',
      '--format=%(refname)',
      'refs/gwt-sync-backup',
    ])).toBe('')
    expect(read(repository, 'late-change.txt')).toBe('changed after preflight\n')
  })

  it('fzf 交互期间变 dirty 时自动保护并执行无冲突更新', () => {
    const repository = createRepository()
    write(repository, 'base.txt', 'base\n')
    git(repository, ['add', 'base.txt'])
    git(repository, ['commit', '-m', 'base'])

    const remote = createBareRepository()
    git(repository, ['remote', 'add', 'origin', remote])
    git(repository, ['push', '--set-upstream', 'origin', 'main'])
    git(repository, ['branch', 'feature'])

    write(repository, 'main.txt', 'main update\n')
    git(repository, ['add', 'main.txt'])
    git(repository, ['commit', '-m', 'main update'])
    git(repository, ['push', 'origin', 'main'])
    const target = git(repository, ['rev-parse', 'main']).trim()
    git(repository, ['checkout', 'feature'])

    const { fakeBin, promptLog } = createFirstChoiceFzf()

    const result = Bun.spawnSync([
      'bun',
      'run',
      join(import.meta.dir, 'gwt-sync.ts'),
      repository,
    ], {
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        PATH: `${fakeBin}:${process.env.PATH ?? ''}`,
        GWT_SYNC_TEST_PROMPT_LOG: promptLog,
        GWT_SYNC_TEST_REPOSITORY: repository,
        GWT_SYNC_TEST_DIRTY_ON_WORKTREE: '1',
      },
    })
    const stderr = result.stderr.toString()
    const prompts = readFileSync(promptLog, 'utf8')

    expect(result.exitCode).toBe(0)
    expect(prompts).toContain('Worktree > ')
    expect(prompts).toContain('Target > ')
    expect(prompts).not.toContain('Dirty action > ')
    expect(prompts).toContain('Confirm > ')
    expect(stderr).toContain('updated to origin/main via ff-only')
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(target)
    expect(read(repository, 'late.txt')).toBe('late local change\n')
    expect(git(repository, ['stash', 'list'])).toBe('')
    expect(git(repository, [
      'for-each-ref',
      '--format=%(refname)',
      'refs/gwt-sync-backup',
    ])).toBe('')
  })

  it('普通冲突进入最终确认并默认取消，不创建 stash 或移动分支', () => {
    const { repository, featureHead } = createBehindConflictFixture()

    const {
      fakeBin,
      promptLog,
      headerLog,
      previewLog,
      deltaLog,
    } = createFirstChoiceFzf()
    const result = Bun.spawnSync([
      'bun',
      'run',
      join(import.meta.dir, 'gwt-sync.ts'),
      repository,
    ], {
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        PATH: `${fakeBin}:${process.env.PATH ?? ''}`,
        GWT_SYNC_TEST_PROMPT_LOG: promptLog,
        GWT_SYNC_TEST_REPOSITORY: repository,
        GWT_SYNC_TEST_HEADER_LOG: headerLog,
        GWT_SYNC_TEST_PREVIEW_LOG: previewLog,
        GWT_SYNC_TEST_DELTA_LOG: deltaLog,
      },
    })
    const stderr = result.stderr.toString()
    const prompts = readFileSync(promptLog, 'utf8')
    const header = readFileSync(headerLog, 'utf8')
    const preview = readFileSync(previewLog, 'utf8')
    const deltaArgs = readFileSync(deltaLog, 'utf8')

    expect(result.exitCode).toBe(0)
    expect(prompts).toContain('Confirm > ')
    expect(prompts).not.toContain('Dirty action > ')
    expect(header).toContain('Conflicts (1): shared.txt')
    expect(header).toContain('Review preview ^e/^y')
    expect(preview).toContain('diff --git a/shared.txt b/shared.txt')
    expect(preview).toContain('<<<<<<<')
    expect(deltaArgs).toContain('--paging=never --side-by-side')
    expect(stderr).toContain('Preflight detected a Git conflict')
    expect(stderr).toContain('Cancelled; branch was not updated')
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(featureHead)
    expect(read(repository, 'shared.txt')).toBe('local change\n')
    expect(git(repository, ['stash', 'list'])).toBe('')
    expect(git(repository, [
      'for-each-ref',
      '--format=%(refname)',
      'refs/gwt-sync-backup',
    ])).toBe('')
  })

  it('普通冲突明确继续后尝试更新并保留恢复入口', () => {
    const { repository, target } = createBehindConflictFixture()
    const { fakeBin, promptLog } = createFirstChoiceFzf()
    const result = Bun.spawnSync([
      'bun',
      'run',
      join(import.meta.dir, 'gwt-sync.ts'),
      repository,
    ], {
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        ...process.env,
        PATH: `${fakeBin}:${process.env.PATH ?? ''}`,
        GWT_SYNC_TEST_PROMPT_LOG: promptLog,
        GWT_SYNC_TEST_REPOSITORY: repository,
        GWT_SYNC_TEST_CONFIRM_SECOND: '1',
      },
    })
    const stderr = result.stderr.toString()
    const prompts = readFileSync(promptLog, 'utf8')

    expect(result.exitCode).toBe(1)
    expect(prompts).toContain('Confirm > ')
    expect(stderr).toContain('local changes could not be restored')
    expect(stderr).not.toContain('stash apply --index')
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(target)
    expect(git(repository, ['status', '--porcelain'])).toContain('UU shared.txt')
    expect(git(repository, ['stash', 'list'])).toContain('gwt-sync: feature -> origin/main')
    expect(git(repository, [
      'for-each-ref',
      '--format=%(refname)',
      'refs/gwt-sync-backup',
    ])).toContain('refs/gwt-sync-backup/')
  })

  it('JSON 默认只预检并输出明确的 worktree、目标和有效策略', () => {
    const { repository, featureHead } = createBehindFixture()
    const worktree = git(repository, ['rev-parse', '--show-toplevel']).trim()
    const result = runJsonCli([
      '--worktree',
      repository,
      '--target',
      'origin/main',
      '--strategy',
      'rebase',
      '--json',
    ])
    const output = parseJsonResult(result)

    expect(result.exitCode).toBe(0)
    expect(result.stderr?.toString() ?? '').toBe('')
    expect(output).toMatchObject({
      schemaVersion: 1,
      ok: true,
      mode: 'inspect',
      outcome: 'ready',
      worktree: {
        path: worktree,
        branch: 'feature',
        head: featureHead,
        dirty: false,
      },
      target: {
        ref: 'origin/main',
        remote: 'origin',
        branch: 'main',
      },
      relation: {
        ahead: 0,
        behind: 1,
        relation: 'behind',
      },
      strategy: {
        requested: 'rebase',
        effective: 'ff-only',
      },
      preflight: {
        ok: true,
        conflicts: { files: [], diff: null },
      },
      update: { attempted: false, applied: false },
    })
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(featureHead)
  })

  it('JSON 冲突结果包含文件、冲突内容和 dirty 状态且不修改分支', () => {
    const { repository, featureHead } = createBehindConflictFixture()
    const worktree = git(repository, ['rev-parse', '--show-toplevel']).trim()
    const result = runJsonCli([
      '--worktree',
      repository,
      '--target',
      'origin/main',
      '--json',
    ])
    const output = parseJsonResult(result)

    expect(result.exitCode).toBe(2)
    expect(result.stderr?.toString() ?? '').toBe('')
    expect(output).toMatchObject({
      ok: false,
      mode: 'inspect',
      outcome: 'conflict',
      worktree: {
        path: worktree,
        branch: 'feature',
        head: featureHead,
        dirty: true,
        status: {
          staged: 0,
          unstaged: 1,
          untracked: 0,
          changes: [{ path: 'shared.txt', index: ' ', worktree: 'M' }],
        },
      },
      target: {
        ref: 'origin/main',
        remote: 'origin',
        branch: 'main',
      },
      preflight: {
        ok: false,
        allowAttempt: true,
        conflicts: { files: ['shared.txt'] },
      },
      update: { attempted: false, applied: false },
    })
    expect(output.preflight?.conflicts.diff).toContain('diff --git a/shared.txt b/shared.txt')
    expect(output.preflight?.conflicts.diff).toContain('<<<<<<<')
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(featureHead)
    expect(read(repository, 'shared.txt')).toBe('local change\n')
  })

  it('JSON 仅在双重授权后尝试冲突更新并返回恢复命令', () => {
    const { repository, target } = createBehindConflictFixture()
    const result = runJsonCli([
      '--worktree',
      repository,
      '--target',
      'origin/main',
      '--apply',
      '--allow-conflicts',
      '--json',
    ])
    const output = parseJsonResult(result)

    expect(result.exitCode).toBe(4)
    expect(result.stderr?.toString() ?? '').toBe('')
    expect(output).toMatchObject({
      ok: false,
      mode: 'apply',
      outcome: 'failed',
      preflight: {
        ok: false,
        allowAttempt: true,
        conflicts: { files: ['shared.txt'] },
      },
      update: {
        attempted: true,
        applied: false,
        stage: 'stash-apply',
      },
    })
    expect(output.recovery?.commands).toEqual(expect.arrayContaining([
      {
        action: 'inspect-status',
        argv: ['git', '-C', expect.any(String), 'status'],
      },
      {
        action: 'inspect-diff',
        argv: ['git', '-C', expect.any(String), 'diff', '--cached'],
      },
      {
        action: 'inspect-stash',
        argv: ['git', '-C', expect.any(String), 'stash', 'list'],
      },
    ]))
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(target)
    expect(git(repository, ['status', '--porcelain'])).toContain('UU shared.txt')
    expect(git(repository, ['stash', 'list'])).toContain('gwt-sync: feature -> origin/main')
  })

  it('PATH 可执行入口用 --apply 更新分支且 stdout 仅包含 JSON', () => {
    const { repository, target } = createBehindFixture()
    const executable = join(import.meta.dir, '../../../../.local/bin/gwt-sync')
    const result = runJsonCli([
      '--worktree',
      repository,
      '--target',
      'origin/main',
      '--apply',
      '--json',
    ], executable)
    const output = parseJsonResult(result)

    expect(result.exitCode).toBe(0)
    expect(result.stderr?.toString() ?? '').toBe('')
    expect(output).toMatchObject({
      ok: true,
      mode: 'apply',
      outcome: 'updated',
      strategy: { requested: null, effective: 'ff-only' },
      update: {
        attempted: true,
        applied: true,
        head: target,
      },
    })
    expect(git(repository, ['rev-parse', 'HEAD']).trim()).toBe(target)
  })

  it('恢复计划只在 update 阶段建议匹配的 abort，恢复后阶段不重复 apply', () => {
    const updateFailure = {
      ok: false as const,
      stage: 'update' as const,
      details: 'rebase failed',
      backupRef: 'refs/gwt-sync-backup/test',
      stashOid: '1111111111111111111111111111111111111111',
    }
    const applyFailure = {
      ok: false as const,
      stage: 'stash-apply' as const,
      details: 'stash apply failed',
      backupRef: 'refs/gwt-sync-backup/test',
      stashOid: '2222222222222222222222222222222222222222',
    }
    const verifyFailure = {
      ok: false as const,
      stage: 'verify' as const,
      details: 'verify failed',
      backupRef: 'refs/gwt-sync-backup/test',
      stashOid: '3333333333333333333333333333333333333333',
    }

    expect(planRecovery(updateFailure, 'rebase')).toEqual([
      'inspect-status',
      'abort-rebase',
      'inspect-stash',
      'inspect-backup',
    ])
    expect(planRecovery(applyFailure, 'rebase')).toEqual([
      'inspect-status',
      'inspect-diff',
      'inspect-stash',
      'inspect-backup',
    ])
    expect(planRecovery(verifyFailure, 'merge')).toEqual([
      'inspect-status',
      'inspect-diff',
      'inspect-stash',
      'inspect-backup',
    ])
  })

  it('解析包含 detached、locked 和 prunable 状态的 worktree 机器格式', () => {
    const records = parseWorktreePorcelain([
      'worktree /repo',
      'HEAD 1111111111111111111111111111111111111111',
      'branch refs/heads/main',
      '',
      'worktree /repo/wt',
      'HEAD 2222222222222222222222222222222222222222',
      'detached',
      'locked portable drive',
      'prunable gitdir file points to non-existent location',
      '',
    ].join('\0'))

    expect(records).toEqual([
      {
        path: '/repo',
        head: '1111111111111111111111111111111111111111',
        branch: 'main',
        bare: false,
        detached: false,
        locked: undefined,
        prunable: undefined,
      },
      {
        path: '/repo/wt',
        head: '2222222222222222222222222222222222222222',
        branch: undefined,
        bare: false,
        detached: true,
        locked: 'portable drive',
        prunable: 'gitdir file points to non-existent location',
      },
    ])
  })
})

function createRepository(): string {
  const repository = createTemporaryDirectory('gwt-sync-test-')
  git(repository, ['init', '--initial-branch=main'])
  git(repository, ['config', 'user.name', 'gwt-sync test'])
  git(repository, ['config', 'user.email', 'gwt-sync@example.invalid'])
  return repository
}

function createBareRepository(): string {
  const repository = createTemporaryDirectory('gwt-sync-bare-')
  git(repository, ['init', '--bare'])
  return repository
}

function createBehindConflictFixture(): {
  repository: string
  featureHead: string
  target: string
} {
  const repository = createRepository()
  write(repository, 'shared.txt', 'base\n')
  git(repository, ['add', 'shared.txt'])
  git(repository, ['commit', '-m', 'base'])

  const remote = createBareRepository()
  git(repository, ['remote', 'add', 'origin', remote])
  git(repository, ['push', '--set-upstream', 'origin', 'main'])
  git(repository, ['branch', 'feature'])

  write(repository, 'shared.txt', 'target change\n')
  git(repository, ['commit', '-am', 'main conflict'])
  git(repository, ['push', 'origin', 'main'])
  const target = git(repository, ['rev-parse', 'HEAD']).trim()
  git(repository, ['checkout', 'feature'])
  const featureHead = git(repository, ['rev-parse', 'HEAD']).trim()
  write(repository, 'shared.txt', 'local change\n')
  return { repository, featureHead, target }
}

function createBehindFixture(): {
  repository: string
  featureHead: string
  target: string
} {
  const repository = createRepository()
  write(repository, 'base.txt', 'base\n')
  git(repository, ['add', 'base.txt'])
  git(repository, ['commit', '-m', 'base'])

  const remote = createBareRepository()
  git(repository, ['remote', 'add', 'origin', remote])
  git(repository, ['push', '--set-upstream', 'origin', 'main'])
  git(repository, ['branch', 'feature'])

  write(repository, 'main.txt', 'main update\n')
  git(repository, ['add', 'main.txt'])
  git(repository, ['commit', '-m', 'main update'])
  git(repository, ['push', 'origin', 'main'])
  const target = git(repository, ['rev-parse', 'HEAD']).trim()
  git(repository, ['checkout', 'feature'])
  const featureHead = git(repository, ['rev-parse', 'HEAD']).trim()
  return { repository, featureHead, target }
}

function runJsonCli(args: string[], executable?: string): Bun.SyncSubprocess {
  return Bun.spawnSync(
    executable
      ? [executable, ...args]
      : ['bun', 'run', join(import.meta.dir, 'gwt-sync.ts'), ...args],
    {
      stdout: 'pipe',
      stderr: 'pipe',
    },
  )
}

function parseJsonResult(result: Bun.SyncSubprocess): JsonCliResult {
  if (!result.stdout) throw new Error('Expected gwt-sync to return JSON on stdout')
  return JSON.parse(result.stdout.toString()) as JsonCliResult
}

function createTemporaryDirectory(prefix: string): string {
  const directory = mkdtempSync(join(tmpdir(), prefix))
  temporaryRepositories.push(directory)
  return directory
}

function createFirstChoiceFzf(): FakeFzfFixture {
  const fakeBin = createTemporaryDirectory('gwt-sync-fake-bin-')
  const promptLog = join(fakeBin, 'prompts.log')
  const headerLog = join(fakeBin, 'headers.log')
  const previewLog = join(fakeBin, 'preview.log')
  const deltaLog = join(fakeBin, 'delta.log')
  const fakeFzf = join(fakeBin, 'fzf')
  const fakeDelta = join(fakeBin, 'delta')
  writeFileSync(
    fakeFzf,
    [
      '#!/bin/sh',
      'prompt=\'\'',
      'header=\'\'',
      'preview=\'\'',
      'previous=\'\'',
      'for argument in "$@"; do',
      '  if [ "$previous" = "--prompt" ]; then',
      '    prompt=$argument',
      '  elif [ "$previous" = "--header" ]; then',
      '    header=$argument',
      '  elif [ "$previous" = "--preview" ]; then',
      '    preview=$argument',
      '  fi',
      '  previous=$argument',
      'done',
      'input=$(cat)',
      'printf \'%s\\n\' "$prompt" >> "$GWT_SYNC_TEST_PROMPT_LOG"',
      'if [ "$prompt" = "Confirm > " ] && [ -n "${GWT_SYNC_TEST_HEADER_LOG:-}" ]; then',
      '  printf \'%s\\n\' "$header" > "$GWT_SYNC_TEST_HEADER_LOG"',
      'fi',
      'if [ "$prompt" = "Confirm > " ] && [ -n "${GWT_SYNC_TEST_PREVIEW_LOG:-}" ] && [ -n "$preview" ]; then',
      '  /bin/sh -c "$preview" > "$GWT_SYNC_TEST_PREVIEW_LOG"',
      'fi',
      'if [ "$prompt" = "Worktree > " ] && [ "${GWT_SYNC_TEST_DIRTY_ON_WORKTREE:-}" = "1" ]; then',
      '  printf \'late local change\\n\' > "$GWT_SYNC_TEST_REPOSITORY/late.txt"',
      'fi',
      'if [ "$prompt" = "Confirm > " ] && [ "${GWT_SYNC_TEST_CONFIRM_SECOND:-}" = "1" ]; then',
      '  printf \'%s\\n\' "$input" | sed -n \'2p\'',
      'else',
      '  printf \'%s\\n\' "$input" | sed -n \'1p\'',
      'fi',
      '',
    ].join('\n'),
  )
  writeFileSync(
    fakeDelta,
    [
      '#!/bin/sh',
      'if [ -n "${GWT_SYNC_TEST_DELTA_LOG:-}" ]; then',
      '  printf \'%s\\n\' "$*" > "$GWT_SYNC_TEST_DELTA_LOG"',
      'fi',
      'cat',
      '',
    ].join('\n'),
  )
  chmodSync(fakeFzf, 0o755)
  chmodSync(fakeDelta, 0o755)
  return { fakeBin, promptLog, headerLog, previewLog, deltaLog }
}

interface FakeFzfFixture {
  fakeBin: string
  promptLog: string
  headerLog: string
  previewLog: string
  deltaLog: string
}

interface JsonCliResult {
  schemaVersion: number
  ok: boolean
  mode: string
  outcome: string
  worktree?: {
    path: string
    branch: string
    head: string
    dirty: boolean
  }
  preflight?: {
    conflicts: {
      diff: string | null
    }
  } | null
  recovery?: {
    commands: Array<{
      action: string
      argv: string[]
    }>
  }
}

function git(repository: string, args: string[]): string {
  const result = Bun.spawnSync(['git', '-C', repository, ...args], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  if (result.exitCode !== 0) {
    throw new Error(
      [
        `git ${args.join(' ')} failed`,
        result.stderr.toString(),
        result.stdout.toString(),
      ].filter(Boolean).join('\n'),
    )
  }
  return result.stdout.toString()
}

function write(repository: string, path: string, content: string): void {
  writeFileSync(join(repository, path), content)
}

function read(repository: string, path: string): string {
  return readFileSync(join(repository, path), 'utf8')
}
