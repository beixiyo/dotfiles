# Dev guide: Zsh & Bun collaboration

This directory uses **"Zsh thin shell, Bun as core"**: Bun handles fzf construction & data processing, Zsh only does operations that must run in the current shell (cd / export)

## Core architecture

| Layer | Responsibility | Location |
| :--- | :--- | :--- |
| **Shared utils (zsh)** | `has`, `require`, `log_*`, `is_mac`, `confirm` | `functions/utils/*.zsh` |
| **Shared utils (TS)** | `log`, `die`, `assertCmd`, `hasCmd` | `functions/bun/src/utils.ts` |
| **Zsh thin shell** | cd / export / one-line glue | `functions/*.zsh` |
| **Bun core** | fzf build & spawn, list generation, complex logic | `functions/bun/src/*.ts` |
| **Bash callbacks** | fzf preview / execute / become callbacks | `functions/_preview/*.sh`, `functions/_actions/*.sh` |
| **pkg shared** | Distro detection, PM command builder, desktop refresh | `functions/pkg/_common.zsh` |

---

## Shared utilities convention

### Zsh side (`functions/utils/`)

All zsh files can use these — they are sourced before any module:

```zsh
# check.zsh
has git                    # command exists?
require bun || return 1   # assert or abort with error message
is_mac / is_tty / is_wsl  # environment detection

# log.zsh
log "doing something"     # cyan ▸ prefix, to stderr
log_ok "done"             # green ✔
log_warn "careful"        # yellow ⚠
log_err "failed"          # red ✘
log_dim "secondary info"  # dim text

# interact.zsh
confirm "Delete?" && rm file  # y/N prompt, returns 0 on yes
```

**When adding new functions**: if a pattern repeats across 2+ files, extract it into `utils/`. Source order: `log.zsh` → `check.zsh` → `interact.zsh` (check depends on nothing, interact depends on `is_tty`).

### Bun side (`bun/src/utils.ts`)

```typescript
import { log, logOk, logErr, die, assertCmd, hasCmd } from './utils'

assertCmd('fzf')              // exits with error if missing
if (!hasCmd('delta')) { ... } // boolean check
die('fatal error')            // logErr + process.exit(1)
```

**When adding shared TS logic**: put it in `utils.ts` for general helpers, `fzf-shared.ts` for fzf-specific helpers, `shared.ts` for Nerd Font icons and file-type detection.

### pkg module (`functions/pkg/_common.zsh`)

Reusable across install/uninstall/update/viewer:

```zsh
_pkg_distro_family          # → arch / debian / fedora / suse / alpine / unknown
_pkg_arch_helper            # → paru / yay / pacman
_pkg_cmd install            # → "paru -S --needed" (string, split with ${=result})
_pkg_cmd remove             # → "paru -Rns"
_pkg_cmd upgrade            # → "paru -S --needed" (targeted, not full -Syu)
_pkg_cmd sysupgrade         # → "paru -Syu" (full system upgrade)
_pkg_refresh_desktop        # update-desktop-database + kbuildsycoca6
_pkg_ask_brew               # ask user whether to use Homebrew
```

---

## When to use Bun vs pure Shell vs Bash callbacks

### Use Bun (`bun/src/*.ts`)

- Complex fzf command building (many `--bind`, dynamic args, reload)
- Data generation with logic (JSON, API, formatting, sorting)
- Needs shared config (`fzf-shared.ts`: keybinds, clipboard, spawn helpers)
- Commands with fzf interaction → ~100ms startup is negligible

### Use pure Shell (`functions/*.zsh`)

- One-liners: `mkcd() { mkdir -p "$1" && cd "$1" }`
- Must modify caller's shell state (cd / export) → thin shell wrapping bun
- No interaction, high-frequency calls → bun startup not worth it (~100ms/call)

### Use Bash callback scripts (`_preview/*.sh` / `_actions/*.sh`)

- fzf `--preview`, `--bind execute()`, `--bind become()` callbacks
- Executed by fzf via `$SHELL -c`, must be shell scripts
- Simple content: git commands, editor invocation, clipboard ops
- **Never spawn bun in callbacks** (short-lived, high-frequency, TTY-constrained)

---

## Thin shell templates

```zsh
# 不改 shell 状态 → 纯 bun
gdiff() { bun run "$_DIR/bun/src/gdiff.ts" "$@"; }

# 需要 cd → 一行胶水
grepo() { local d; d=$(bun run "$_DIR/bun/src/grepo.ts" "$@") && [[ -d "$d" ]] && cd "$d"; }

# 需要 export → eval 胶水
setProxy() { eval "$(bun run "$_DIR/bun/src/proxy.ts" set "$@")"; }
```

---

## Bun spawn fzf patterns

### Pattern A: Bun build + spawn (primary)

```typescript
import { spawnFzf } from './fzf-shared'

const list = await generateList()
const genList = `bun run '${BUN_SRC}/list.ts' 2>/dev/null < /dev/null`

await spawnFzf([
  '--ansi',
  '--preview', `${FUNC_DIR}/_preview/xxx.sh {}`,
  '--bind', `ctrl-r:reload:${genList}`,
  '--bind', 'enter:execute(nvim {} < /dev/tty)+abort',
], list)
```

- 初始列表：TypeScript 生成，`Buffer.from(list)` 喂 fzf stdin
- reload：fzf 自行调 bun 数据脚本（shell 命令字符串，**末尾加 `< /dev/null`**）
- preview / execute / become：引用 bash 回调脚本
- fzf TUI 渲染走 `/dev/tty`，不受 stdin/stdout 重定向影响

### Pattern B: Streaming pipe (large data, no buffering)

```typescript
const git = Bun.spawn(['git', 'log', ...], { stdout: 'pipe' })
const fzf = Bun.spawn(['fzf', ...args], { stdin: git.stdout })
await fzf.exited
```

### Pattern C: Capture fzf output (e.g. grepo returns path for zsh cd)

```typescript
import { spawnFzfCapture } from './fzf-shared'

const [exitCode, selected] = await spawnFzfCapture([...args], input)
if (selected) process.stdout.write(selected)  // zsh $() 捕获
```

### Pattern D: Bun outputs shell fragments, Zsh eval

```typescript
// proxy.ts
console.log('export PROXY_URL="http://127.0.0.1:7890"')
```

---

## Data source script conventions (invoked by fzf reload)

These scripts are triggered by fzf `reload:bun run xxx.ts`, output and exit:

- Use `process.stdout.write(line + '\n')`, not `console.log` (avoids buffering/misalignment)
- End with `process.exit(0)`
- When also imported, guard with `import.meta.main`:

```typescript
export async function generateList(): Promise<string> { ... }

if (import.meta.main) {
  const list = await generateList()
  if (list) process.stdout.write(list + '\n')
  process.exit(0)
}
```

---

## TTY & stdin pitfalls

### reload commands must close stdin

fzf reload subprocess stdin is still connected to TTY → competes with fzf for keystrokes → intermittent `^[[B`

```typescript
// 构建 reload 命令时末尾加 < /dev/null
const genList = `bun run '${BUN_SRC}/list.ts' 2>/dev/null < /dev/null`
```

### Use `{}` for preview, not `{q}`

`{q}` is the query string (doesn't change on navigation), `{}` is the current line (updates with cursor)

### Commands needing TTY inside execute() must add `< /dev/tty`

```typescript
'--bind', 'enter:execute(nvim {3} < /dev/tty)+abort'
```

### Streaming output: use writeSync + explicit exit

```typescript
import { writeSync } from 'node:fs'

await Promise.all(items.map(async (x) => {
  const r = await work(x)
  writeSync(1, `${r}\n`)   // 绕过 stdout 缓冲，即时进管道
}))
process.exit(0)            // 不等 pending timer
```

---

## Module index

| Module | Purpose | Used by |
|--------|---------|---------|
| `utils.ts` | Logging, assertions, command detection | All scripts |
| `fzf-shared.ts` | fzf keybinds, clipboard detection, spawn helpers | All `*-cmd.ts` |
| `shared.ts` | Nerd Font icons, ANSI colors, runWithTty | Data source scripts (git.ts, ff-list.ts, etc.) |

---

## Quick troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `^[[B` / broken keys after reload | reload subprocess stdin connected to TTY | Add ` < /dev/null` to reload command |
| Arrow keys garbled after streaming | Bun has pending timer, won't exit | Add `process.exit(0)` at end |
| Streaming list appears in batches | Non-TTY stdout block-buffers | Use `writeSync(1, line)` |
| Preview doesn't update on navigation | Preview uses `{q}` | Change to `{}` |
| fzf list misaligned / duplicated | `console.log` or unflushed | `process.stdout.write` + `process.exit(0)` |
