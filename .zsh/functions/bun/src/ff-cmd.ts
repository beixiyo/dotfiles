#!/usr/bin/env bun

import { assertCmd, fzf, FUNC_DIR, BUN_SRC, detectClipCopy, spawnFzf } from './fzf-shared'

async function main(): Promise<void> {
  assertCmd('fzf')

  let dir = '.'
  let typeFlag = 'a'
  let noIgnore = ''
  const positional: string[] = []
  const argv = process.argv.slice(2)

  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '-d': case '--dir': typeFlag = 'd'; break
      case '-f': case '--file': typeFlag = 'f'; break
      case '-a': case '--all': typeFlag = 'a'; break
      case '-I': case '--no-ignore': noIgnore = '--no-ignore'; break
      case '--': positional.push(...argv.slice(i + 1)); i = argv.length; break
      default: if (!argv[i].startsWith('-')) positional.push(argv[i])
    }
  }
  if (positional.length > 0) dir = positional[0]

  const listArgs = ['run', `${BUN_SRC}/ff-list.ts`, '--dir', dir, '--type', typeFlag]
  if (noIgnore) listArgs.push(noIgnore)

  const listResult = Bun.spawnSync(['bun', ...listArgs], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const list = listResult.stdout.toString()

  const noIgnoreStr = noIgnore ? ` ${noIgnore}` : ''
  const mkReload = (t: string) =>
    `bun run '${BUN_SRC}/ff-list.ts' --dir '${dir}' --type ${t}${noIgnoreStr} 2>/dev/null < /dev/null`

  const clipCmd = detectClipCopy()
  const copyAbs = `bun run '${BUN_SRC}/path.ts' abs {+2} 2>/dev/null | ${clipCmd}`

  const header = [
    `CTRL-O: Code | ${fzf.optLabel}-O: nvim`,
    'CTRL-N/P: navigate | CTRL-E/Y: scroll preview',
    `${fzf.optLabel}-C: copy absolute path`,
    `${fzf.optLabel}-F/D/A: files/dirs/all`,
  ].join('\n')

  await spawnFzf([
    '--delimiter', '\x01',
    '--with-nth', '1,2',
    '--preview', `${FUNC_DIR}/_preview/ff.sh {2}`,
    '--header', header,
    '--bind', fzf.scrollBinds,
    '--bind', fzf.tabToggleDown,
    '--bind', `${fzf.cmd}-o:execute(code {2})`,
    '--bind', `${fzf.opt}-o:execute(nvim {2} < /dev/tty)`,
    '--bind', `${fzf.opt}-c:execute(${copyAbs})`,
    '--bind', `enter:become(${FUNC_DIR}/_actions/ff-select.sh {2} '${BUN_SRC}/path.ts')`,
    '--ansi',
    '--bind', `${fzf.opt}-f:reload(${mkReload('f')})`,
    '--bind', `${fzf.opt}-d:reload(${mkReload('d')})`,
    '--bind', `${fzf.opt}-a:reload(${mkReload('a')})`,
  ], list)
}

main().catch(() => process.exit(1))
