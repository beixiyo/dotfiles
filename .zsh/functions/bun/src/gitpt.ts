#!/usr/bin/env bun

/**
 * 发布稳定 SemVer Git tag，默认使用下一个 patch 版本
 */

import { createInterface } from 'node:readline/promises'
import { parseArgs } from 'node:util'
import type { ReleaseTarget, VersionSourceMode } from './release/types'
import { resolveReleaseTarget } from './release/version-source'
import { assertCmd, die, log, logOk, logWarn } from './utils'

type VersionTools = typeof import('./version')

function git(args: string[], output: 'pipe' | 'inherit' = 'pipe') {
  return Bun.spawnSync(['git', ...args], {
    stdin: output,
    stdout: output,
    stderr: output,
  })
}

function gitText(args: string[]): string {
  const result = git(args)
  if (result.exitCode !== 0) {
    die(result.stderr?.toString().trim() || `Git command failed: git ${args.join(' ')}`)
  }
  return result.stdout?.toString().trim() ?? ''
}

async function loadVersionTools(): Promise<VersionTools> {
  try {
    return await import('./version')
  }
  catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (message.includes('semver')) {
      die('Missing semver dependency; run: bun install --cwd ~/.zsh/functions/bun')
    }
    throw error
  }
}

async function promptInitialVersion(): Promise<string> {
  if (!process.stdin.isTTY) {
    die('No stable SemVer tag found; pass the initial version: gitpt <version>')
  }

  const prompt = createInterface({ input: process.stdin, output: process.stdout })
  const version = await prompt.question('Initial release version (e.g. v0.1.0): ')
  prompt.close()
  return version.trim()
}

async function confirmCandidateOrPromptVersion(candidateTag: string, source: string): Promise<string> {
  if (!process.stdin.isTTY) {
    die(`Release tag requires confirmation; pass it explicitly: gitpt ${candidateTag}`)
  }

  const prompt = createInterface({ input: process.stdin, output: process.stdout })
  const confirmation = await prompt.question(`Publish ${source} tag ${candidateTag}? [y/N]: `)

  if (confirmation.trim().toLowerCase() === 'y') {
    prompt.close()
    return candidateTag
  }

  const tag = await prompt.question('Release tag: ')
  prompt.close()
  return tag.trim()
}

function tagPrefix(latestTag: { prefix: '' | 'v' } | null): '' | 'v' {
  return latestTag?.prefix ?? 'v'
}

function targetDescription(target: ReleaseTarget | null): string {
  if (!target) return 'patch'
  if (target.source === 'go-mod') return `Go module ${target.packageName ?? target.manifestPath}`
  return `${target.source} ${target.packageName ?? target.manifestPath}`
}

async function main(): Promise<void> {
  assertCmd('git')

  let parsed: ReturnType<typeof parseArgs>
  try {
    parsed = parseArgs({
      args: process.argv.slice(2),
      allowPositionals: true,
      options: {
        remote: { type: 'string', short: 'r', default: 'origin' },
        versionSource: { type: 'string', default: 'tag' },
        manifest: { type: 'string' },
        force: { type: 'boolean', short: 'f' },
        help: { type: 'boolean', short: 'h' },
      },
    })
  }
  catch (error) {
    die(error instanceof Error ? error.message : String(error))
  }

  if (parsed.values.help) {
    console.log('Usage: gitpt [version] [-r remote] [-f|--force] [--version-source tag|manifest|auto] [--manifest path]')
    return
  }
  if (parsed.positionals.length > 1) die('Usage: gitpt [version] [-r remote] [-f|--force] [--version-source tag|manifest|auto] [--manifest path]')

  const {
    formatVersionTag,
    incrementPatchTag,
    isGreaterVersionTag,
    latestStableVersionTag,
    parseVersionTag,
  } = await loadVersionTools()
  const remote = parsed.values.remote as string
  const requestedTag = parsed.positionals[0]
  const versionSource = parsed.values.versionSource as string as VersionSourceMode
  const manifestPath = parsed.values.manifest as string | undefined
  const force = parsed.values.force === true

  if (git(['rev-parse', '--is-inside-work-tree']).exitCode !== 0) {
    die('Not inside a Git repository')
  }
  const repoRoot = gitText(['rev-parse', '--show-toplevel'])
  if (gitText(['status', '--porcelain'])) {
    if (!force) die('Working tree is not clean; pass --force to publish from the current HEAD')
    logWarn('Working tree is dirty; the tag will point to HEAD and exclude uncommitted changes')
  }
  if (git(['remote', 'get-url', remote]).exitCode !== 0) die(`Git remote not found: ${remote}`)

  let target: ReleaseTarget | null
  try {
    target = await resolveReleaseTarget({
      mode: versionSource,
      repoRoot,
      manifestPath,
    })
  }
  catch (error) {
    die(error instanceof Error ? error.message : String(error))
  }

  log(`Fetching tags from ${remote}`)
  if (git(['fetch', '--tags', '--quiet', remote]).exitCode !== 0) {
    die(`Failed to fetch tags from ${remote}`)
  }

  const latestTag = latestStableVersionTag(
    gitText(['tag', '--merged', 'HEAD']).split('\n').filter(Boolean),
    target?.tagScope ?? '',
    target?.tagMajor,
  )

  if (latestTag && gitText(['rev-list', `${latestTag.tag}..HEAD`, '--count']) === '0') {
    die(`No commits after ${latestTag.tag}`)
  }

  let nextTag = requestedTag

  if (!nextTag && (latestTag || target?.version)) {
    const candidateTag = target?.version
      ? formatVersionTag(target.version, {
        prefix: tagPrefix(latestTag),
        scope: target.tagScope,
      })
      : incrementPatchTag(latestTag!)
    nextTag = await confirmCandidateOrPromptVersion(
      candidateTag,
      targetDescription(target),
    )
  }
  if (!nextTag) {
    nextTag = await promptInitialVersion()
  }

  const requestedTagWithScope = target?.tagScope && !nextTag.startsWith(target.tagScope)
    ? `${target.tagScope}${nextTag}`
    : nextTag
  nextTag = requestedTagWithScope
  const parsedNextTag = parseVersionTag(nextTag, target?.tagScope ?? '')

  if (!parsedNextTag) {
    die(`Invalid SemVer tag: ${nextTag || '<empty>'}`)
  }
  if (target?.tagMajor !== undefined && parsedNextTag.semver.major !== target.tagMajor) {
    die(`Go module requires major version v${target.tagMajor}: ${nextTag}`)
  }
  if (git(['show-ref', '--verify', '--quiet', `refs/tags/${nextTag}`]).exitCode === 0) {
    die(`Tag already exists: ${nextTag}`)
  }
  if (latestTag && !isGreaterVersionTag(parsedNextTag, latestTag)) {
    die(`Version must be greater than ${latestTag.tag}: ${nextTag}`)
  }

  log(
    latestTag
      ? `Publishing ${nextTag} from ${latestTag.tag}`
      : `Publishing initial tag ${nextTag}`,
  )

  if (git(['tag', '-a', nextTag, '-m', `Release ${nextTag}`], 'inherit').exitCode !== 0) {
    process.exit(1)
  }
  if (git(['push', remote, `refs/tags/${nextTag}`], 'inherit').exitCode !== 0) {
    die(`Push failed; local tag remains: ${nextTag}`)
  }

  logOk(`Published ${nextTag}`)
}

main().catch((error) => die(error instanceof Error ? error.message : String(error)))
