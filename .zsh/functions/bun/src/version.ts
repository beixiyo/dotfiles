/**
 * 解析并比较基于 SemVer 的 Git tag
 */

import { compare, inc, parse, SemVer } from 'semver'

export interface VersionTag {
  tag: string
  semver: SemVer
  prefix: '' | 'v'
  scope: string
}

/**
 * 解析严格 SemVer tag，同时允许 Git 常见的 `v` 前缀
 */
export function parseVersionTag(tag: string, scope = ''): VersionTag | null {
  if (scope && !tag.startsWith(scope)) return null

  const scopedTag = scope ? tag.slice(scope.length) : tag
  const prefix = scopedTag.startsWith('v') ? 'v' : ''
  const semver = parse(prefix ? scopedTag.slice(1) : scopedTag)

  return semver
    ? { tag, semver, prefix, scope }
    : null
}

/**
 * 找出指定 scope 和 major 版本下最高的稳定 SemVer tag
 */
export function latestStableVersionTag(tags: string[], scope = '', major?: number): VersionTag | null {
  return tags
    .map((tag) => parseVersionTag(tag, scope))
    .filter((tag): tag is VersionTag =>
      tag !== null
      && tag.semver.prerelease.length === 0
      && (major === undefined || tag.semver.major === major)
    )
    .sort((left, right) => compare(right.semver, left.semver))[0]
    ?? null
}

/**
 * 按 SemVer 优先级比较两个有效 tag
 */
export function isGreaterVersionTag(candidate: VersionTag, current: VersionTag): boolean {
  return compare(candidate.semver, current.semver) > 0
}

/**
 * 增加稳定 tag 的 patch，并保留原有的 scope 和 `v` 前缀
 */
export function incrementPatchTag(tag: VersionTag): string {
  const nextVersion = inc(tag.semver, 'patch')
  if (!nextVersion) throw new Error(`Cannot increment version: ${tag.tag}`)

  return `${tag.scope}${tag.prefix}${nextVersion}`
}

/**
 * 将项目 manifest 版本格式化为 Git tag
 */
export function formatVersionTag(version: string, options: {
  prefix?: '' | 'v'
  scope?: string
} = {}): string {
  const parsed = parseVersionTag(version)
  if (!parsed) throw new Error(`Invalid SemVer version: ${version}`)

  const build = parsed.semver.build.length > 0
    ? `+${parsed.semver.build.join('.')}`
    : ''

  return `${options.scope ?? ''}${options.prefix ?? 'v'}${parsed.semver.version}${build}`
}
