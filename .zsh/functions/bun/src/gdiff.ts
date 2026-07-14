#!/usr/bin/env bun

import { existsSync, statSync } from 'node:fs'
import { assertCmd, fzf, FUNC_DIR, BUN_SRC, shellQuote, spawnFzf } from './fzf-shared'
import { generateStatusList } from './git'

async function main(): Promise<void> {
  assertCmd('git')
  assertCmd('fzf')

  let targetDir = '.'
  const positional: string[] = []
  const argv = process.argv.slice(2)

  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--') { positional.push(...argv.slice(i + 1)); break }
    if (argv[i].startsWith('-')) continue
    positional.push(argv[i])
  }
  if (positional.length > 0) targetDir = positional[0]

  if (!existsSync(targetDir) || !statSync(targetDir).isDirectory()) {
    console.error(`not a directory: ${targetDir}`)
    process.exit(1)
  }

  const gitCheck = Bun.spawnSync(
    ['git', '-C', targetDir, 'rev-parse', '--is-inside-work-tree'],
    { stdout: 'pipe', stderr: 'pipe' },
  )
  if (gitCheck.exitCode !== 0) {
    console.error(`not a git repository: ${targetDir}`)
    process.exit(1)
  }

  process.chdir(targetDir)

  const list = await generateStatusList()
  const genList = `bun run ${shellQuote(BUN_SRC + '/git.ts')} 2>/dev/null < /dev/null`
  const editor = process.env.EDITOR ?? 'nvim'

  const header = [
    'ENTER: open | CTRL-S: stage/unstage',
    'CTRL-X: discard changes',
    'CTRL-N/P: navigate | CTRL-E/Y: scroll preview',
  ].join('\n')

  await spawnFzf([
    '--ansi',
    '--header', header,
    '--header-first',
    '--with-nth=1,3',
    '--delimiter', '\t',
    '--no-multi',
    '--preview', `${FUNC_DIR}/_preview/git-diff.sh {3}`,
    '--preview-window', fzf.gitPreviewWindow,
    '--bind', fzf.scrollBinds,
    '--bind', `${fzf.cmd}-s:execute(${FUNC_DIR}/_actions/git-toggle-stage.sh {3})+reload:${genList}`,
    '--bind', `${fzf.cmd}-x:execute(${FUNC_DIR}/_actions/git-discard.sh {3} < /dev/tty)+reload:${genList}`,
    '--bind', `enter:execute(${editor} {3} < /dev/tty)+abort`,
  ], list)
}

main().catch(() => process.exit(1))
