#!/usr/bin/env bun

import { existsSync, statSync } from 'node:fs'
import { assertCmd, fzf, FUNC_DIR, BUN_SRC, detectClipCopy, spawnFzf } from './fzf-shared'

async function main(): Promise<void> {
  assertCmd('fzf')

  let dir = '.'
  let noIgnore = ''
  const positional: string[] = []
  const argv = process.argv.slice(2)

  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '-I': case '--no-ignore': noIgnore = '--no-ignore'; break
      case '--': positional.push(...argv.slice(i + 1)); i = argv.length; break
      default: if (!argv[i].startsWith('-')) positional.push(argv[i])
    }
  }
  if (positional.length > 0 && existsSync(positional[0]) && statSync(positional[0]).isDirectory()) {
    dir = positional[0]
  }

  const noIgnoreStr = noIgnore ? ` ${noIgnore}` : ''
  const rgNoIgnore = noIgnore ? ' --no-ignore-vcs' : ''

  const rgBase = `rg --column --line-number --no-heading --color=never --smart-case --hidden --no-ignore-parent${rgNoIgnore} --glob '!.git'`
  const fsChangeReload = `${rgBase} {q} '${dir}' < /dev/null | bun run '${BUN_SRC}/fs-list.ts' 2>/dev/null || true`

  const clipCmd = detectClipCopy()
  const panel = `${FUNC_DIR}/_actions/fx-panel.sh`

  await Bun.write('/tmp/fzf-fx-env', [
    `_FX_FUNC_DIR='${FUNC_DIR}'`,
    `_FX_BUN_SRC='${BUN_SRC}'`,
    `_FX_DIR='${dir}'`,
    `_FX_NO_IGNORE='${noIgnore}'`,
    `_FX_RG_NO_IGNORE='${rgNoIgnore.trim()}'`,
    `_FX_CLIP_CMD='${clipCmd}'`,
  ].join('\n') + '\n')

  const ffReload = `bun run '${BUN_SRC}/ff-list.ts' --dir '${dir}' --type a${noIgnoreStr} 2>/dev/null < /dev/null`

  const listResult = Bun.spawnSync(
    ['bun', 'run', `${BUN_SRC}/ff-list.ts`, '--dir', dir, '--type', 'a', ...(noIgnore ? [noIgnore] : [])],
    { stdout: 'pipe', stderr: 'pipe' },
  )
  const list = listResult.stdout.toString()

  await spawnFzf([
    '--ansi',
    '--delimiter', '\x01',
    '--with-nth', '1,2',
    '--prompt', ' Files> ',
    '--preview', `${FUNC_DIR}/_preview/ff.sh {2}`,
    '--preview-window', 'right:60%:border-left',
    '--bind', fzf.scrollBinds,

    '--bind', `change:reload(${fsChangeReload})`,
    '--bind', `start:unbind(change)+reload(${ffReload})+transform-header(${panel} init)+transform-footer(${panel} footer)`,

    '--bind', `tab:transform(${panel} switch-next {q})`,
    '--bind', `shift-tab:transform(${panel} switch-prev {q})`,
    '--bind', `enter:transform(${panel} enter {2})`,
    '--bind', `click-footer:transform(${panel} click "$FZF_CLICK_FOOTER_WORD" {2})`,

    '--bind', `${fzf.cmd}-o:execute(code {2})`,
    '--bind', `${fzf.opt}-o:execute(nvim {2} < /dev/tty)`,
    '--bind', `${fzf.opt}-c:execute-silent(bun run '${BUN_SRC}/path.ts' abs {+2} 2>/dev/null | ${clipCmd})`,
  ], list)
}

main().catch(() => process.exit(1))
