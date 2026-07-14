import { spawnSync } from 'child_process'

const sourceId = Number.parseInt(process.env.KITTY_WINDOW_ID || '0')
const listenOn = process.env.KITTY_LISTEN_ON || ''

if (!sourceId) process.exit(1)

const rcArgs = listenOn
  ? ['@', '--to', listenOn]
  : ['@']

const ls = spawnSync('kitten', [...rcArgs, 'ls'], { encoding: 'utf-8' })
if (ls.status !== 0) process.exit(1)

const data: any[] = JSON.parse(ls.stdout)

const shellQuote = (value: string): string => `'${value.replace(/'/g, `'\\''`)}'`

const isVimWindow = (win: any): boolean => {
  const procs: any[] = win.foreground_processes ?? []

  return procs.some((p: any) => {
    const name = (p.cmdline?.[0] ?? '').split('/').pop() ?? ''
    return name === 'vim' || name === 'nvim'
  })
}

const restoreLocation = (source: any, target: any): string => {
  const neighbors = source.neighbors ?? {}

  // Kitty 只能近似恢复 split 方向，无法像 tmux 一样无损 join 回原布局。
  if ((neighbors.left ?? []).includes(target.id) || (neighbors.right ?? []).includes(target.id)) {
    return 'vsplit'
  }

  if ((neighbors.top ?? []).includes(target.id) || (neighbors.bottom ?? []).includes(target.id)) {
    return 'hsplit'
  }

  return 'vsplit'
}

for (const osWin of data) {
  for (const tab of osWin.tabs ?? []) {
    const wins: any[] = tab.windows ?? []
    const source = wins.find(win => win.id === sourceId)
    if (!source) continue

    // 优先同 tab 的非 Vim window；这最符合“另一侧 AI pane”的直觉。
    let target = wins.find(win => win.id !== sourceId && !isVimWindow(win))

    // 兜底到同一个 OS window 的其他 tab，保持旧 send-to-window.ts 的行为范围。
    if (!target) {
      target = (osWin.tabs ?? [])
        .flatMap((item: any) => item.windows ?? [])
        .find((win: any) => win.id !== sourceId && !isVimWindow(win))
    }

    if (!target) process.exit(1)

    const values: Record<string, string> = {
      NVD_KITTY_LISTEN_ON: listenOn,
      NVD_KITTY_ORIGIN_WINDOW: String(sourceId),
      NVD_KITTY_TARGET_WINDOW: String(target.id),
      NVD_KITTY_RESTORE_LOCATION: restoreLocation(source, target),
    }

    for (const [key, value] of Object.entries(values)) {
      console.log(`${key}=${shellQuote(value)}`)
    }

    process.exit(0)
  }
}

process.exit(1)
