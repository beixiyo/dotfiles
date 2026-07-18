#!/usr/bin/env bun

import { assertCmd, BUN_SRC, fzf, spawnFzfCapture } from './fzf-shared'

const DOCKER_BUN = `${BUN_SRC}/docker.ts`

async function main(): Promise<void> {
  assertCmd('docker')
  assertCmd('fzf')

  const genList = `bun run '${DOCKER_BUN}' list 2>/dev/null < /dev/null`
  const dispatchCmd = `bun run '${DOCKER_BUN}' dispatch`

  const listResult = Bun.spawnSync(
    ['bun', 'run', DOCKER_BUN, 'list'],
    { stdout: 'pipe', stderr: 'pipe' },
  )
  const list = listResult.stdout.toString()

  const guide = [
    'Multi ⇥ │ Logs l │ Exec e │ Copy ID c │ Stop s │ Run r │ Restart R',
    'Remove container d │ Remove image i │ Refresh ^R',
  ].join('\n')

  const [, selected] = await spawnFzfCapture([
    '-m',
    '--bind', fzf.tabToggleDown,
    '--with-nth', '2..',
    '--header', guide,
    '--header-lines', '0',
    '--bind', `l:execute(${dispatchCmd} logs {+} </dev/tty)+abort`,
    '--bind', `e:execute(${dispatchCmd} exec {+} </dev/tty)+abort`,
    '--bind', `c:execute(${dispatchCmd} copy {+})+abort`,
    '--bind', `s:execute(${dispatchCmd} stop {+})+abort`,
    '--bind', `r:execute(${dispatchCmd} run {+})+abort`,
    '--bind', `R:execute(${dispatchCmd} restart {+})+abort`,
    '--bind', `d:execute(${dispatchCmd} delete {+})+abort`,
    '--bind', `i:execute(${dispatchCmd} image {+})+abort`,
    '--bind', `ctrl-r:reload:${genList}`,
  ], list)

  if (selected) {
    const choice = selected
      .split('\n')
      .map(l => {
        const fields = l.split('\t')
        return fields.length >= 3 ? fields[2] : ''
      })
      .filter(Boolean)
      .join('\n')

    if (choice) console.log(`Selected: ${choice}`)
  }
}

main().catch(() => process.exit(1))
