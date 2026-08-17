/**
 * 从 Node 和 Bun 的 package.json manifest 读取发布版本
 */

import { join } from 'node:path'
import type { ReleaseTarget, VersionSource } from '../types'

interface PackageJson {
  name?: unknown
  version?: unknown
  private?: unknown
  workspaces?: unknown
}

async function readPackageJson(repoRoot: string, manifestPath: string): Promise<PackageJson> {
  const file = Bun.file(join(repoRoot, manifestPath))
  if (!(await file.exists())) {
    throw new Error(`Manifest not found: ${manifestPath}`)
  }

  try {
    return JSON.parse(await file.text()) as PackageJson
  }
  catch (error) {
    throw new Error(`Invalid JSON in ${manifestPath}: ${error instanceof Error ? error.message : String(error)}`)
  }
}

function toTarget(manifestPath: string, data: PackageJson): ReleaseTarget {
  if (typeof data.version !== 'string' || data.version.length === 0) {
    throw new Error(`Missing string version in ${manifestPath}`)
  }

  return {
    source: 'package-json',
    manifestPath,
    packageName: typeof data.name === 'string' ? data.name : undefined,
    version: data.version,
    tagScope: '',
  }
}

export const packageJsonSource: VersionSource = {
  id: 'package-json',

  async discover(repoRoot) {
    const manifestPath = 'package.json'
    const file = Bun.file(join(repoRoot, manifestPath))
    if (!(await file.exists())) return []
    const data = await readPackageJson(repoRoot, manifestPath)

    if (data.private === true || data.workspaces !== undefined) return []
    if (typeof data.version !== 'string' || data.version.length === 0) return []

    return [toTarget(manifestPath, data)]
  },

  async read(repoRoot, manifestPath) {
    return toTarget(manifestPath, await readPackageJson(repoRoot, manifestPath))
  },
}
