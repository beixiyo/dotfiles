import readline from 'node:readline'
import { loadFiles, loadDict, COLORS_ANSI, type IconEntry } from './icons-shared'

/** 共享数据源：加载期一次性读取（files / directories / extensions） */
const FILES_JSON: Record<string, IconEntry> = loadFiles('files')
const DIRS_JSON: Record<string, IconEntry> = loadDict('directories')
const EXTS_JSON: Record<string, IconEntry> = loadDict('extensions')

/**
 * 三种 lookup 都支持偏字段条目（仅 glyph 或仅 color）：
 *   - glyph 缺省 → 用类目默认（文件夹 / file_default）
 *   - color 缺省 → 用类目默认（DIR_ICON_COLOR / COLORS.White）
 * 这样 JSON 里 `{ "color": "purple" }` 或 `{ "glyph": "..." }` 都是合法写法。
 */
function lookupFile(base: string): { icon: string; color: string } | null {
  const e = FILES_JSON[base]
  if (!e) return null
  return {
    icon: e.glyph ?? ICONS.file_default,
    color: e.color ? COLORS_ANSI[e.color] : COLORS.White,
  }
}

function lookupDir(base: string): { icon: string; color: string } | null {
  const e = DIRS_JSON[base]
  if (!e) return null
  return {
    icon: e.glyph ?? ICONS.folder,
    color: e.color ? COLORS_ANSI[e.color] : DIR_ICON_COLOR,
  }
}

function lookupExt(ext: string): { icon: string; color: string } | null {
  const e = EXTS_JSON[ext]
  if (!e) return null
  return {
    icon: e.glyph ?? ICONS.file_default,
    color: e.color ? COLORS_ANSI[e.color] : COLORS.White,
  }
}

/** 交互式确认（y/Y 返回 true） */
export async function confirm(prompt: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  })

  return await new Promise((resolve) => {
    rl.question(prompt, (answer) => {
      rl.close()
      resolve(/^[Yy]$/.test(answer.trim()))
    })
  })
}

/**
 * 在指定目录下以继承 TTY 的方式执行命令。
 * 子进程的 stdin/stdout/stderr 直接继承当前进程，保证 process.stdout.isTTY 为 true，
 * 供 Nx、交互式 dev server、watch 模式测试等 CLI 正常使用。
 *
 * @param cwd 工作目录
 * @param cmd 命令与参数，如 ['pnpm', 'build'] 或 ['npm', 'run', 'dev']
 * @param options.env 可选，与 process.env 合并后传给子进程
 * @returns 子进程退出码
 */
export async function runWithTty(
  cwd: string,
  cmd: string[],
  options?: { env?: Record<string, string | undefined> },
): Promise<number> {
  const [exe, ...args] = cmd
  const proc = Bun.spawn([exe, ...args], {
    cwd,
    stdio: ['inherit', 'inherit', 'inherit'],
    env: options?.env ? { ...process.env, ...options.env } : undefined,
  })
  return await proc.exited
}

export const COLORS = {
  Black: '\x1b[30m',
  Red: '\x1b[31m',
  Green: '\x1b[32m',
  Yellow: '\x1b[33m',
  Blue: '\x1b[34m',
  Magenta: '\x1b[35m',
  Cyan: '\x1b[36m',
  White: '\x1b[37m',
  Reset: '\x1b[0m',
}

/**
 * Nerd Font 通用图标（非文件类）。文件 / 扩展名图标统一在 data/*.json 中维护。
 *
 * 用法示例：`${COLORS.Blue}${ICONS.docker}${COLORS.Reset}`
 */
export const ICONS = {
  docker: '',
  git: '',
  git_merge: '',
  git_commit: '',
  git_branch: '',
  folder: '',
  folder_opened: '',
  diff_added: '',
  diff_modified: '',
  diff_removed: '',
  container: '',
  file_default: '',
} as const

/** 取路径最后一段，先去掉尾随 / 再切（避免 fd 输出 ./.github/ 得到空串） */
function basename(path: string): string {
  const trimmed = path.replace(/\/+$/, '')
  const i = trimmed.lastIndexOf('/')
  return i >= 0 ? trimmed.slice(i + 1) : trimmed
}

/** 目录图标颜色 */
export const DIR_ICON_COLOR = COLORS.Blue

/**
 * 取文件/目录的彩色 glyph。匹配优先级：
 *   目录：directories.json → 默认蓝文件夹
 *   文件：files.json → extensions.json → 默认（白 file_default）
 * 文件名查询会同时尝试原始大小写与 lowercase（兼容 Cargo.lock 与全小写两种约定）。
 */
export function getFileIconColored(name: string, isDir: boolean): string {
  const base = basename(name)
  const baseLower = base.toLowerCase()

  if (isDir) {
    const dir = lookupDir(base) ?? lookupDir(baseLower)
    const icon = dir?.icon ?? ICONS.folder
    const color = dir?.color ?? DIR_ICON_COLOR
    return `${color}${icon}${COLORS.Reset}`
  }

  const fileMatch = lookupFile(base) ?? lookupFile(baseLower)
  if (fileMatch) return `${fileMatch.color}${fileMatch.icon}${COLORS.Reset}`

  const ext = baseLower.includes('.') ? baseLower.slice(baseLower.lastIndexOf('.') + 1) : ''
  const extMatch = lookupExt(ext)
  if (extMatch) return `${extMatch.color}${extMatch.icon}${COLORS.Reset}`

  return `${COLORS.White}${ICONS.file_default}${COLORS.Reset}`
}
