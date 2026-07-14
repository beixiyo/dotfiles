/** 已安装包信息 */
export interface PkgInfo {
  name: string
  version: string
  size: string
  sizeBytes: number
  description: string
}

/** 包管理器适配器 */
export interface PkgAdapter {
  list(): Promise<PkgInfo[]>
}

/** 字节数 → 人类可读大小 */
export function formatSize(bytes: number): string {
  if (bytes <= 0) return '0 B'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KiB`
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(1)} MiB`
  return `${(bytes / 1024 ** 3).toFixed(1)} GiB`
}

/**
 * 解析人类可读大小 → 字节数
 * 支持 pacman 的 "45.23 MiB"、"1024.00 KiB" 等格式
 */
export function parseSizeToBytes(size: string): number {
  const match = size.match(/([\d.]+)\s*(B|KiB|MiB|GiB|TiB|KB|MB|GB|TB)/)
  if (!match) return 0
  const val = parseFloat(match[1])
  const units: Record<string, number> = {
    B: 1,
    KB: 1e3, MB: 1e6, GB: 1e9, TB: 1e12,
    KiB: 1024, MiB: 1024 ** 2, GiB: 1024 ** 3, TiB: 1024 ** 4,
  }
  return Math.round(val * (units[match[2]] || 1))
}

/** 运行命令并返回 stdout 文本 */
export async function exec(cmd: string[]): Promise<string> {
  const proc = Bun.spawn(cmd, { stdout: 'pipe', stderr: 'pipe' })
  const text = await new Response(proc.stdout).text()
  await proc.exited
  return text
}

/** 运行 shell 命令并返回 stdout 文本 */
export async function execSh(cmd: string): Promise<string> {
  const proc = Bun.spawn(['sh', '-c', cmd], { stdout: 'pipe', stderr: 'pipe' })
  const text = await new Response(proc.stdout).text()
  await proc.exited
  return text
}
