import { parseSizeToBytes } from './types'
import type { PkgAdapter, PkgInfo } from './types'

export function createPacmanAdapter(): PkgAdapter {
  return {
    async list() {
      const proc = Bun.spawn(['pacman', '-Qi'], { stdout: 'pipe', stderr: 'pipe', env: { ...process.env, LC_ALL: 'C' } })
      const text = await new Response(proc.stdout).text()
      await proc.exited

      const pkgs: PkgInfo[] = []

      for (const block of text.split('\n\n')) {
        if (!block.trim()) continue
        const f = parseBlock(block)
        if (!f.Name) continue

        const size = f['Installed Size'] || '0 B'
        pkgs.push({
          name: f.Name,
          version: f.Version || '',
          size,
          sizeBytes: parseSizeToBytes(size),
          description: f.Description || '',
        })
      }

      return pkgs
    },
  }
}

/**
 * 解析 `pacman -Qi` 的 key-value 块
 * 每行格式："Key            : Value"，续行以空格缩进
 */
function parseBlock(block: string): Record<string, string> {
  const result: Record<string, string> = {}
  let key = ''

  for (const line of block.split('\n')) {
    const m = line.match(/^([A-Za-z][\w\s]*?)\s*:\s*(.*)$/)
    if (m) {
      key = m[1].trim()
      result[key] = m[2].trim()
    } else if (key && line.startsWith(' ')) {
      result[key] += ' ' + line.trim()
    }
  }

  return result
}
