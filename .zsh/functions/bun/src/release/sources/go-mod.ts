/**
 * 从 go.mod 解析 Go module 的 tag scope 和 major 版本
 */

import { dirname, join, relative } from 'node:path'
import type { ReleaseTarget, VersionSource } from '../types'

async function readModulePath(repoRoot: string, manifestPath: string): Promise<string> {
  const file = Bun.file(join(repoRoot, manifestPath))
  if (!(await file.exists())) {
    throw new Error(`Manifest not found: ${manifestPath}`)
  }

  const text = await file.text()
  const match = text.match(/^\s*module\s+([^\s#]+)/m)
  if (!match) throw new Error(`Missing module directive in ${manifestPath}`)
  return match[1]
}

function tagScope(repoRoot: string, manifestPath: string, modulePath: string): {
  scope: string
  major?: number
} {
  const directory = relative(repoRoot, join(repoRoot, dirname(manifestPath)))
  let scope = directory ? `${directory}/` : ''
  const majorMatch = modulePath.match(/\/v([2-9]\d*)$/)
  const major = majorMatch ? Number(majorMatch[1]) : undefined

  if (major !== undefined) {
    const majorDirectory = `v${major}/`
    if (scope.endsWith(majorDirectory)) {
      scope = scope.slice(0, -majorDirectory.length)
    }
  }

  return { scope, major }
}

async function readTarget(repoRoot: string, manifestPath: string): Promise<ReleaseTarget> {
  const modulePath = await readModulePath(repoRoot, manifestPath)
  const tag = tagScope(repoRoot, manifestPath, modulePath)

  return {
    source: 'go-mod',
    manifestPath,
    packageName: modulePath,
    version: null,
    tagScope: tag.scope,
    tagMajor: tag.major,
  }
}

export const goModSource: VersionSource = {
  id: 'go-mod',

  async discover(repoRoot) {
    const manifestPath = 'go.mod'
    const file = Bun.file(join(repoRoot, manifestPath))
    if (!(await file.exists())) return []
    return [await readTarget(repoRoot, manifestPath)]
  },

  read: readTarget,
}
