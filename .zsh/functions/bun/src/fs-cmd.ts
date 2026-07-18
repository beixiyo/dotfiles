#!/usr/bin/env bun

import { assertCmd, fzf, FUNC_DIR, BUN_SRC, detectClipCopy, shellQuote, spawnFzf } from './fzf-shared'
import { existsSync, statSync } from 'node:fs'

async function main(): Promise<void> {
  assertCmd('fzf')
  assertCmd('rg')

  let dir = '.'
  let noIgnore = ''
  const positional: string[] = []
  const argv = process.argv.slice(2)

  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '-I': case '--no-ignore': noIgnore = '--no-ignore-vcs'; break
      case '--': positional.push(...argv.slice(i + 1)); i = argv.length; break
      default: if (!argv[i].startsWith('-')) positional.push(argv[i])
    }
  }
  if (positional.length > 0 && existsSync(positional[0]) && statSync(positional[0]).isDirectory()) {
    dir = positional[0]
  }

  const rgBase = [
    '--column', '--line-number', '--no-heading', '--color=never',
    '--smart-case', '--hidden', '--no-ignore-parent',
    ...(noIgnore ? [noIgnore] : []),
    '--glob', '!.git',
  ]

  const rg = Bun.spawn(
    ['rg', ...rgBase, '', dir],
    { stdout: 'pipe', stderr: 'pipe' },
  )
  const fsFilter = Bun.spawn(
    ['bun', 'run', `${BUN_SRC}/fs-list.ts`],
    { stdin: rg.stdout, stdout: 'pipe', stderr: 'pipe' },
  )
  const list = await new Response(fsFilter.stdout).text()
  await rg.exited
  await fsFilter.exited

  const rgCmdStr = `rg --column --line-number --no-heading --color=never --smart-case --hidden --no-ignore-parent${noIgnore ? ' ' + noIgnore : ''} --glob '!.git'`

  const reloadStart = `${rgCmdStr} '' ${shellQuote(dir)} < /dev/null | bun run '${BUN_SRC}/fs-list.ts' 2>/dev/null`
  const reloadChange = `${rgCmdStr} {q} ${shellQuote(dir)} < /dev/null | bun run '${BUN_SRC}/fs-list.ts' 2>/dev/null || true`

  const clipCmd = detectClipCopy()
  const copyAbs = `bun run '${BUN_SRC}/path.ts' abs {+2} 2>/dev/null | ${clipCmd}`

  const header = [
    `Select ↵ │ Code ${fzf.cmdHint}O │ nvim ${fzf.optHint}O │ Copy ${fzf.optHint}C`,
    `Navigate ${fzf.cmdHint}N/${fzf.cmdHint}P │ Preview ^E/^Y`,
  ].join('\n')

  await spawnFzf([
    '--disabled',
    '--ansi',
    '--delimiter', '\x01',
    '--with-nth', '1,2',
    '--preview', `${FUNC_DIR}/_preview/fs.sh {2}`,
    '--preview-window', 'right:60%:border-left',
    '--bind', `start:reload(${reloadStart})`,
    '--bind', `change:reload(${reloadChange})`,
    '--header', header,
    '--bind', fzf.scrollBinds,
    '--bind', fzf.tabToggleDown,
    '--bind', `${fzf.cmd}-o:execute(code -g "$(echo {2} | cut -d: -f1):$(echo {2} | cut -d: -f2)")`,
    '--bind', `${fzf.opt}-o:execute(nvim "+$(echo {2} | cut -d: -f2)" "$(echo {2} | cut -d: -f1)" < /dev/tty)`,
    '--bind', `${fzf.opt}-c:execute(${copyAbs})`,
    '--bind', `enter:become(${FUNC_DIR}/_actions/fs-select.sh {2} '${BUN_SRC}/path.ts')`,
  ], list)
}

main().catch(() => process.exit(1))
