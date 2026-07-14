import { spawnSync } from 'child_process'

const chunks: Buffer[] = []
for await (const chunk of process.stdin) chunks.push(chunk as Buffer)
const text = Buffer.concat(chunks).toString()

const list = spawnSync('wezterm', ['cli', 'list', '--format', 'json'], { encoding: 'utf-8' })
if (list.status !== 0) process.exit(1)

const panes: any[] = JSON.parse(list.stdout)
const currentId = parseInt(process.env.WEZTERM_PANE ?? '0')

const currentWindow = panes.find(p => p.pane_id === currentId)?.window_id
if (currentWindow === undefined) process.exit(1)

for (const pane of panes) {
  if (pane.window_id !== currentWindow || pane.pane_id === currentId) continue
  const title = (pane.title ?? '').toLowerCase()
  if (title.includes('nvim') || title === 'vim') continue

  spawnSync(
    'wezterm',
    ['cli', 'send-text', '--pane-id', String(pane.pane_id), text],
    { encoding: 'utf-8' },
  )
  process.exit(0)
}

process.exit(1)
