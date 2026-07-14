import { spawnSync } from 'child_process'

const chunks: Buffer[] = []
for await (const chunk of process.stdin) chunks.push(chunk as Buffer)
const text = Buffer.concat(chunks).toString()

const listenOn = process.env.NVD_KITTY_LISTEN_ON || process.env.KITTY_LISTEN_ON
const rcArgs = listenOn
  ? ['@', '--to', listenOn]
  : ['@']

const ls = spawnSync('kitten', [...rcArgs, 'ls'], { encoding: 'utf-8' })
if (ls.status !== 0) process.exit(1)

const data: any[] = JSON.parse(ls.stdout)
const directTargetId = parseInt(process.env.NVD_KITTY_TARGET_WINDOW || '0')
const currentId = parseInt(process.env.NVD_KITTY_ORIGIN_WINDOW || process.env.KITTY_WINDOW_ID || '0')
if (!directTargetId && !currentId) process.exit(1)

const isVimWindow = (win: any): boolean => {
  const procs: any[] = win.foreground_processes ?? []

  return procs.some((p: any) => {
    const name = (p.cmdline?.[0] ?? '').split('/').pop() ?? ''
    return name === 'vim' || name === 'nvim'
  })
}

const sendToWindow = (id: number): void => {
  spawnSync(
    'kitten',
    [...rcArgs, 'send-text', '--match', `id:${id}`, '--stdin', '--bracketed-paste', 'auto'],
    { input: text, encoding: 'utf-8' },
  )
  process.exit(0)
}

if (directTargetId) {
  for (const osWin of data) {
    const allWins: any[] = (osWin.tabs ?? []).flatMap((t: any) => t.windows ?? [])
    const target = allWins.find(win => win.id === directTargetId)

    if (target && !isVimWindow(target)) sendToWindow(target.id)
  }

  process.exit(1)
}

for (const osWin of data) {
  const allWins: any[] = (osWin.tabs ?? []).flatMap((t: any) => t.windows ?? [])
  if (!allWins.some(w => w.id === currentId)) continue

  for (const win of allWins) {
    if (win.id === currentId) continue
    if (isVimWindow(win)) continue

    sendToWindow(win.id)
  }
}

process.exit(1)
