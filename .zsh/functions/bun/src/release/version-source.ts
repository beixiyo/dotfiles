/**
 * 从显式指定或自动检测的项目来源中解析发布目标
 */

import { relative, resolve } from 'node:path'
import { cargoTomlSource } from './sources/cargo-toml'
import { goModSource } from './sources/go-mod'
import { packageJsonSource } from './sources/package-json'
import { type ReleaseTarget, sourceIdForManifest, type VersionSource, type VersionSourceMode } from './types'

const sources: VersionSource[] = [packageJsonSource, cargoTomlSource, goModSource]

function relativeManifestPath(repoRoot: string, manifestPath: string): string {
  const root = resolve(repoRoot)
  const absolute = resolve(root, manifestPath)
  const relativePath = relative(root, absolute)

  if (relativePath.startsWith('..') || relativePath === '..') {
    throw new Error(`Manifest must be inside the repository: ${manifestPath}`)
  }

  return relativePath || manifestPath
}

/**
 * 解析 CLI 选择的项目发布目标
 *
 * `tag` 返回 null，因为 Git tag 由调用方解析；`auto` 在没有找到支持的
 * 项目 manifest 时也返回 null
 */
export async function resolveReleaseTarget(options: {
  mode: VersionSourceMode
  repoRoot: string
  manifestPath?: string
}): Promise<ReleaseTarget | null> {
  const { mode, repoRoot, manifestPath } = options

  if (!['tag', 'manifest', 'auto'].includes(mode)) {
    throw new Error(`Invalid version source: ${mode}. Use tag, manifest, or auto`)
  }

  if (manifestPath) {
    const relativePath = relativeManifestPath(repoRoot, manifestPath)
    const sourceId = sourceIdForManifest(relativePath)
    const source = sources.find((candidate) => candidate.id === sourceId)
    if (!source) {
      throw new Error(`Unsupported manifest: ${manifestPath}`)
    }
    return source.read(repoRoot, relativePath)
  }

  if (mode === 'tag') return null

  const candidates = (await Promise.all(
    sources.map((source) => source.discover(repoRoot)),
  )).flat()

  if (candidates.length === 0) {
    if (mode === 'manifest') {
      throw new Error('No supported release manifest found; pass --manifest <path>')
    }
    return null
  }

  if (candidates.length > 1) {
    const paths = candidates.map((candidate) => candidate.manifestPath).join(', ')
    throw new Error(`Multiple release manifests found: ${paths}; pass --manifest <path>`)
  }

  return candidates[0]
}
