/**
 * 从 Cargo package 和 workspace manifest 读取发布版本
 */

import { dirname, join } from 'node:path'
import type { ReleaseTarget, VersionSource } from '../types'

interface CargoPackage {
  name?: unknown
  version?: unknown
}

interface CargoManifest {
  package?: CargoPackage
  workspace?: {
    package?: {
      version?: unknown
    }
  }
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined
}

async function readCargoManifest(repoRoot: string, manifestPath: string): Promise<CargoManifest> {
  const file = Bun.file(join(repoRoot, manifestPath))
  if (!(await file.exists())) {
    throw new Error(`Manifest not found: ${manifestPath}`)
  }

  try {
    return Bun.TOML.parse(await file.text()) as CargoManifest
  }
  catch (error) {
    throw new Error(`Invalid TOML in ${manifestPath}: ${error instanceof Error ? error.message : String(error)}`)
  }
}

async function findWorkspaceVersion(repoRoot: string, manifestPath: string): Promise<string | undefined> {
  let directory = dirname(manifestPath)

  while (true) {
    const candidatePath = directory === '.' ? 'Cargo.toml' : join(directory, 'Cargo.toml')
    const candidateFile = Bun.file(join(repoRoot, candidatePath))
    if (!(await candidateFile.exists())) {
      if (directory === '.') return undefined
      const parent = dirname(directory)
      directory = parent === directory ? '.' : parent
      continue
    }
    const candidate = await readCargoManifest(repoRoot, candidatePath)
    const version = stringValue(candidate.workspace?.package?.version)
    if (version) return version

    if (directory === '.') return undefined
    const parent = dirname(directory)
    directory = parent === directory ? '.' : parent
  }
}

async function resolveVersion(repoRoot: string, manifestPath: string, manifest: CargoManifest): Promise<string | undefined> {
  const packageVersion = manifest.package?.version
  const directVersion = stringValue(packageVersion)
  if (directVersion) return directVersion

  if (
    typeof packageVersion === 'object'
    && packageVersion !== null
    && 'workspace' in packageVersion
    && packageVersion.workspace === true
  ) {
    return findWorkspaceVersion(repoRoot, manifestPath)
  }

  const workspaceVersion = stringValue(manifest.workspace?.package?.version)
  if (workspaceVersion) return workspaceVersion
  return undefined
}

function createTarget(manifestPath: string, manifest: CargoManifest, version: string | undefined, requirePackage: boolean): ReleaseTarget {
  const packageName = stringValue(manifest.package?.name)
  if (requirePackage && !packageName) {
    throw new Error(`${manifestPath} is a Cargo workspace manifest; pass a specific package manifest`)
  }
  if (!version) {
    throw new Error(`Missing Cargo package version in ${manifestPath}`)
  }

  return {
    source: 'cargo-toml',
    manifestPath,
    packageName,
    version,
    tagScope: '',
  }
}

export const cargoTomlSource: VersionSource = {
  id: 'cargo-toml',

  async discover(repoRoot) {
    const manifestPath = 'Cargo.toml'
    const file = Bun.file(join(repoRoot, manifestPath))
    if (!(await file.exists())) return []
    const manifest = await readCargoManifest(repoRoot, manifestPath)
    if (!stringValue(manifest.package?.name)) return []

    const version = await resolveVersion(repoRoot, manifestPath, manifest)
    if (!version) return []

    return [createTarget(manifestPath, manifest, version, true)]
  },

  async read(repoRoot, manifestPath) {
    const manifest = await readCargoManifest(repoRoot, manifestPath)
    const version = await resolveVersion(repoRoot, manifestPath, manifest)
    return createTarget(manifestPath, manifest, version, true)
  },
}
