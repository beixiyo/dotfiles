import path from 'node:path'

/**
 * 路径与敏感文件规则（Read 与 Bash 共用）
 *
 * 既拦 Read 工具直接读，也拦 Bash 里 cat/grep/cp/xxd/source/< 重定向 等迂回读取
 * 仅做静态安全判定，不调用 shell，也不展开其他变量、glob 或命令替换
 */
export const HOME = process.env.HOME ?? ''

/** 把路径开头的 `~`、`$HOME` 或 `${HOME}` 统一成 HOME 绝对路径 */
export const expandHome = (p: string): string => {
  if (p === '~') return HOME
  if (p.startsWith('~/')) return HOME + p.slice(1)

  return p
    .replace(/^\$\{HOME\}(?=\/|$)/, HOME)
    .replace(/^\$HOME(?=\/|$)/, HOME)
}

/**
 * 敏感路径匹配器：对「规范化后的路径」逐条 test
 *
 * 用 (^|/) 锚定路径段起点，兼容绝对路径、~ 展开后路径、以及相对路径（如 .ssh/id_rsa）
 * .env 段尾用 (?!.*example) 放行 .env.example，与原 Read 规则一致
 */
export const SENSITIVE: Array<{ re: RegExp; reason: string }> = [
  { re: /(^|\/)\.[^/]*env(?!.*example)[^/]*$/i, reason: '访问 .env 敏感文件' },
  { re: /(^|\/)\.ssh(\/|$)/i, reason: '访问 .ssh 凭据' },
  { re: /(^|\/)\.gnupg(\/|$)/i, reason: '访问 .gnupg 密钥' },
  { re: /(^|\/)\.aws(\/|$)/i, reason: '访问 .aws 凭据' },
  { re: /(^|\/)\.netrc$/i, reason: '访问 .netrc' },
]

// 这些目录树下的任意目标都视为危险；macOS 的 /etc、/var 实际落在 /private 下，显式覆盖两种写法
const RM_PROTECTED_TREES = [
  '/bin', '/boot', '/dev', '/etc', '/lib', '/lib64', '/opt', '/proc', '/root', '/sbin', '/sys',
  '/usr', '/var', '/System', '/Library', '/Applications', '/private/etc', '/private/var',
]

// 这些只是容器根：拒绝根本身及直接 glob，但不把 HOME、挂载盘或 /private/tmp 下的普通文件全部判危险
const RM_PROTECTED_ROOTS = ['/private', '/Users', '/Volumes']

const isDirectGlob = (candidate: string, root: string): boolean => {
  if (!candidate.startsWith(`${root}/`)) return false

  const relative = candidate.slice(root.length + 1)
  return !relative.includes('/') && /[*?\[\]{}]/.test(relative)
}

const isWithin = (candidate: string, root: string): boolean =>
  candidate === root || candidate.startsWith(`${root}/`)

/** 单个 rm 目标 token 是否危险（根 / 当前或上级目录 / 家目录 / 系统树 / .git / 动态目标） */
export const isDangerousRmTarget = (token: string, cwd: string): boolean => {
  if (token === '') return false

  // 动态命令替换无法静态确认最终目标，按危险处理
  if (/`|\$\(/.test(token)) return true

  const expanded = expandHome(token)

  // 删除前先按 cwd 做词法归一化，堵住 ~/.config/..、$HOME/.、foo/.. 等等价写法
  const normalized = path.resolve(cwd, expanded).replace(/\/+$/, '') || '/'

  // 根 / 当前或上级目录整体 / 家目录（含变量、引号和父目录折叠后的等价形式）
  if (normalized === '/' || normalized === cwd || normalized === path.dirname(cwd)) return true
  // .git 目录（呼应「递归删除曾删光含 .git 的项目」教训）
  if (/(?:^|\/)\.git(?:\/|$)/.test(expanded)) return true
  if (RM_PROTECTED_TREES.some(root => isWithin(normalized, root))) return true
  if (RM_PROTECTED_ROOTS.some(root => normalized === root || isDirectGlob(normalized, root))) return true

  if (HOME && (normalized === HOME || isDirectGlob(normalized, HOME))) return true

  return false
}
