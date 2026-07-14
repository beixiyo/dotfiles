import { formatSize } from './types'
import type { PkgAdapter, PkgInfo } from './types'

export function createAptAdapter(): PkgAdapter {
  return {
    async list() {
      // Installed-Size 单位为 KiB
      const fmt = '${Package}\\t${Version}\\t${Installed-Size}\\t${Description}\\n'
      const proc = Bun.spawn(['dpkg-query', '-W', `-f=${fmt}`], {
        stdout: 'pipe',
        stderr: 'pipe',
      })
      const text = await new Response(proc.stdout).text()
      await proc.exited

      const pkgs: PkgInfo[] = []

      for (const line of text.split('\n')) {
        if (!line.trim()) continue
        const parts = line.split('\t')
        if (parts.length < 3) continue

        const [name, version, sizeKB, ...descParts] = parts
        if (!name) continue

        const sizeBytes = (parseInt(sizeKB, 10) || 0) * 1024
        pkgs.push({
          name,
          version: version || '',
          size: formatSize(sizeBytes),
          sizeBytes,
          // dpkg Description 首行为摘要，后续为长描述
          description: (descParts.join(' ').split('\n')[0] || '').trim(),
        })
      }

      return pkgs
    },
  }
}
