/**
 * Parse and compare SemVer-based Git tag names.
 */

import { SemVer, compare, inc, parse } from 'semver'

export interface VersionTag {
  tag: string
  semver: SemVer
  prefix: '' | 'v'
}

/**
 * Parse a strict SemVer tag, allowing the conventional Git `v` prefix.
 */
export function parseVersionTag(tag: string): VersionTag | null {
  const prefix = tag.startsWith('v') ? 'v' : ''
  const semver = parse(prefix ? tag.slice(1) : tag)

  return semver
    ? { tag, semver, prefix }
    : null
}

/**
 * Find the highest stable SemVer tag.
 */
export function latestStableVersionTag(tags: string[]): VersionTag | null {
  return tags
    .map(parseVersionTag)
    .filter((tag): tag is VersionTag => tag !== null && tag.semver.prerelease.length === 0)
    .sort((left, right) => compare(right.semver, left.semver))[0]
    ?? null
}

/**
 * Compare two valid SemVer tags by precedence.
 */
export function isGreaterVersionTag(candidate: VersionTag, current: VersionTag): boolean {
  return compare(candidate.semver, current.semver) > 0
}

/**
 * Increment a stable tag's patch while preserving its `v` prefix style.
 */
export function incrementPatchTag(tag: VersionTag): string {
  const nextVersion = inc(tag.semver, 'patch')
  if (!nextVersion) throw new Error(`Cannot increment version: ${tag.tag}`)

  return `${tag.prefix}${nextVersion}`
}
