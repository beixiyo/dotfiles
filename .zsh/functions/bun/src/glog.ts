#!/usr/bin/env bun

import { assertCmd, fzf, FUNC_DIR } from './fzf-shared'

async function main(): Promise<void> {
  assertCmd('git')
  assertCmd('fzf')

  const logFormat = '%C(auto)%h%d %s %C(black)%C(bold)%cr'

  const git = Bun.spawn(
    ['git', 'log', '--graph', '--color=always', `--format=${logFormat}`, ...process.argv.slice(2)],
    { stdout: 'pipe', stderr: 'inherit' },
  )

  const fzfProc = Bun.spawn([
    'fzf',
    '--ansi',
    '--no-sort',
    '--reverse',
    '--tiebreak=index',
    '--preview', `${FUNC_DIR}/_preview/git-log.sh {}`,
    '--preview-window', fzf.gitPreviewWindow,
    '--bind', fzf.scrollBinds,
    '--header', `Select ↵ │ Navigate ${fzf.cmdHint}N/${fzf.cmdHint}P │ Preview ^E/^Y`,
  ], {
    stdin: git.stdout,
    stdout: 'inherit',
    stderr: 'inherit',
  })

  await fzfProc.exited
}

main().catch(() => process.exit(1))
