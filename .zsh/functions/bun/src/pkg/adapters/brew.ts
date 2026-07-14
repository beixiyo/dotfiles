import { formatSize, execSh } from './types'
import type { PkgAdapter, PkgInfo } from './types'

export function createBrewAdapter(): PkgAdapter {
  return {
    async list() {
      const proc = Bun.spawn(['brew', 'info', '--json=v2', '--installed'], {
        stdout: 'pipe',
        stderr: 'pipe',
      })
      const text = await new Response(proc.stdout).text()
      await proc.exited

      const data = JSON.parse(text) as BrewJSON
      const pkgs: PkgInfo[] = []

      // --- formulae ---
      for (const f of data.formulae || []) {
        const ver = f.installed?.[0]?.version
        if (!ver) continue
        pkgs.push({
          name: f.name,
          version: ver,
          size: '',
          sizeBytes: 0,
          description: f.desc || '',
        })
      }

      // --- casks ---
      for (const c of data.casks || []) {
        if (!c.installed) continue
        pkgs.push({
          name: c.token,
          version: c.installed || '',
          size: '',
          sizeBytes: 0,
          description: c.desc || '',
        })
      }

      // 批量获取 cellar 大小（一次 du 覆盖所有 formula）
      await fillSizesFromCellar(pkgs)

      return pkgs
    },
  }
}

/**
 * 通过 `du -sk $(brew --cellar)/*` 批量获取所有 formula 磁盘占用，
 * 再映射回 pkgs 数组
 */
async function fillSizesFromCellar(pkgs: PkgInfo[]) {
  try {
    const cellar = (await execSh('brew --cellar')).trim()
    if (!cellar) return

    const duText = await execSh(`du -sk "${cellar}"/* 2>/dev/null`)
    const sizeMap = new Map<string, number>()

    for (const line of duText.split('\n')) {
      if (!line) continue
      const tab = line.indexOf('\t')
      if (tab < 0) continue
      const kb = parseInt(line.slice(0, tab), 10) || 0
      const dir = line.slice(tab + 1)
      const name = dir.split('/').pop()!
      sizeMap.set(name, kb * 1024)
    }

    for (const pkg of pkgs) {
      const bytes = sizeMap.get(pkg.name)
      if (bytes !== undefined) {
        pkg.sizeBytes = bytes
        pkg.size = formatSize(bytes)
      }
    }
  } catch {
    // 忽略 —— cask 或未知路径不影响整体列表
  }
}

// --- brew JSON 类型（仅声明用到的字段） ---

type BrewJSON = {
  formulae?: BrewFormula[]
  casks?: BrewCask[]
}

type BrewFormula = {
  name: string
  desc?: string
  installed?: { version: string }[]
}

type BrewCask = {
  token: string
  desc?: string
  installed?: string
}
