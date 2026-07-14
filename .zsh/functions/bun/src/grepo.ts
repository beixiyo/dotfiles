#!/usr/bin/env bun

import { existsSync, statSync } from 'node:fs'
import { assertCmd, fzf, FUNC_DIR, detectClipCopy, shellQuote, spawnFzfCapture } from './fzf-shared'

async function main(): Promise<void> {
  assertCmd('fzf')

  const fdBin = Bun.which('fd') ? 'fd' : Bun.which('fdfind') ? 'fdfind' : null
  if (!fdBin) {
    console.error('fd is required but not installed')
    process.exit(1)
  }

  let searchDir = '.'
  let fdIgnoreFlags = ['--no-ignore-vcs', '--no-ignore-parent']
  let showHidden = false
  const positional: string[] = []
  const argv = process.argv.slice(2)

  for (let i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '-I': case '--no-ignore':
        fdIgnoreFlags = ['--no-ignore', '--no-ignore-parent']; break
      case '-H': case '--hidden':
        showHidden = true; break
      case '--':
        positional.push(...argv.slice(i + 1)); i = argv.length; break
      default:
        if (!argv[i].startsWith('-')) positional.push(argv[i])
    }
  }
  if (positional.length > 0) searchDir = positional[0]

  if (!existsSync(searchDir) || !statSync(searchDir).isDirectory()) {
    console.error(`not a directory: ${searchDir}`)
    process.exit(1)
  }

  const fdResult = Bun.spawnSync(
    [fdBin, '-H', '-t', 'd', '-g', '**/.git', ...fdIgnoreFlags, searchDir],
    { stdout: 'pipe', stderr: 'pipe' },
  )

  let repos = fdResult.stdout.toString()
    .split('\n')
    .filter(l => l.length > 0)
    .map(l => l.replace(/\/\.git\/*$/, ''))

  if (!showHidden) {
    repos = repos.filter(r => !/\/\./.test(r))
  }

  repos = [...new Set(repos)].sort()
  if (repos.length === 0) return

  const clipCmd = detectClipCopy()
  const clipQ = shellQuote(clipCmd)

  const previewCmd = [
    'git -C {} --no-pager remote -v 2>/dev/null',
    'echo',
    'git -C {} --no-pager log -1 --oneline --color=always 2>/dev/null',
    'echo',
    'git -C {} --no-pager status -sb --color=always 2>/dev/null',
  ].join('; ')

  const header = [
    'ENTER: cd to repo',
    `CTRL-O: Code | ${fzf.optLabel}-O: nvim`,
    'CTRL-N/P: navigate | CTRL-E/Y: scroll preview',
    `${fzf.optLabel}-C: copy remote URL`,
    `Ctrl-Alt-C: HTTPS link | ${fzf.optLabel}-P: copy path`,
  ].join('\n')

  const [, selected] = await spawnFzfCapture([
    '--ansi',
    '--preview', previewCmd,
    '--preview-window', fzf.grepoPreviewWindow,
    '--header', header,
    '--header-first',
    '--bind', fzf.scrollBinds,
    '--bind', `${fzf.cmd}-o:execute(code {})`,
    '--bind', `${fzf.opt}-o:execute(nvim {} < /dev/tty)`,
    '--bind', `${fzf.opt}-c:execute(env GREPO_CLIP_CMD=${clipQ} ${FUNC_DIR}/_actions/grepo-copy-url.sh {})`,
    '--bind', `ctrl-alt-c:execute(env GREPO_CLIP_CMD=${clipQ} ${FUNC_DIR}/_actions/grepo-copy-https.sh {})`,
    '--bind', `${fzf.opt}-p:execute-silent(realpath {} | tr -d '\\n' | ${clipCmd})`,
  ], repos.join('\n'))

  if (selected) {
    process.stdout.write(selected)
  }
}

main().catch(() => process.exit(1))
