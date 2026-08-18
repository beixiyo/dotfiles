/**
 * 项目版本来源的共享类型
 */

import { basename } from 'node:path'

/** CLI 选择的版本解析策略 */
export type VersionSourceMode = 'tag' | 'manifest' | 'auto'

/** 支持的项目 manifest 适配器 */
export type ManifestSourceId = 'package-json' | 'cargo-toml' | 'go-mod'

/** 在仓库中发现的可发布包或模块 */
export interface ReleaseTarget {
  source: ManifestSourceId
  manifestPath: string
  packageName?: string
  version: string | null
  tagScope: string
  tagMajor?: number
}

/** 负责发现和读取一种 manifest 格式的适配器 */
export interface VersionSource {
  id: ManifestSourceId
  discover(repoRoot: string): Promise<ReleaseTarget[]>
  read(repoRoot: string, manifestPath: string): Promise<ReleaseTarget>
}

/** 根据支持的 manifest 文件名返回对应的适配器标识 */
export function sourceIdForManifest(manifestPath: string): ManifestSourceId | null {
  const name = basename(manifestPath)
  if (name === 'package.json') return 'package-json'
  if (name === 'Cargo.toml') return 'cargo-toml'
  if (name === 'go.mod') return 'go-mod'
  return null
}
