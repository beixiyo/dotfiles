#!/usr/bin/env bun

/**
 * Publish a stable SemVer Git tag, defaulting to the next patch version.
 */

import { createInterface } from 'node:readline/promises'
import { parseArgs } from 'node:util'
import { assertCmd, die, log, logOk } from './utils'

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

async function confirmPatchOrPromptVersion(patchTag: string): Promise<{
  tag: string
  manual: boolean
}> {
  if (!process.stdin.isTTY) {
    die(`Patch tag requires confirmation; pass it explicitly: gitpt ${patchTag}`)
  }

  const prompt = createInterface({ input: process.stdin, output: process.stdout })
  const confirmation = await prompt.question(`Publish patch tag ${patchTag}? [y/N]: `)

  if (confirmation.trim().toLowerCase() === 'y') {
    prompt.close()
    return { tag: patchTag, manual: false }
  }

  const tag = await prompt.question('Release tag: ')
  prompt.close()
  return { tag: tag.trim(), manual: true }
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
        help: { type: 'boolean', short: 'h' },
      },
    })
  }
  catch (error) {
    die(error instanceof Error ? error.message : String(error))
  }

  if (parsed.values.help) {
    console.log('Usage: gitpt [version] [-r remote]')
    return
  }
  if (parsed.positionals.length > 1) die('Usage: gitpt [version] [-r remote]')

  const {
    incrementPatchTag,
    isGreaterVersionTag,
    latestStableVersionTag,
    parseVersionTag,
  } = await loadVersionTools()
  const remote = parsed.values.remote as string
  const requestedTag = parsed.positionals[0]

  if (git(['rev-parse', '--is-inside-work-tree']).exitCode !== 0) {
    die('Not inside a Git repository')
  }
  if (gitText(['status', '--porcelain'])) die('Working tree is not clean')
  if (git(['remote', 'get-url', remote]).exitCode !== 0) die(`Git remote not found: ${remote}`)

  log(`Fetching tags from ${remote}`)
  if (git(['fetch', '--tags', '--quiet', remote]).exitCode !== 0) {
    die(`Failed to fetch tags from ${remote}`)
  }

  const latestTag = latestStableVersionTag(
    gitText(['tag', '--merged', 'HEAD']).split('\n').filter(Boolean),
  )

  if (latestTag && gitText(['rev-list', `${latestTag.tag}..HEAD`, '--count']) === '0') {
    die(`No commits after ${latestTag.tag}`)
  }

  let nextTag = requestedTag
  let manualTag = requestedTag !== undefined

  if (!nextTag && latestTag) {
    const selection = await confirmPatchOrPromptVersion(incrementPatchTag(latestTag))
    nextTag = selection.tag
    manualTag = selection.manual
  }
  if (!nextTag) {
    nextTag = await promptInitialVersion()
    manualTag = true
  }

  const parsedNextTag = parseVersionTag(nextTag)

  if (!parsedNextTag) {
    die(`Invalid SemVer tag: ${nextTag || '<empty>'}`)
  }
  if (git(['show-ref', '--verify', '--quiet', `refs/tags/${nextTag}`]).exitCode === 0) {
    die(`Tag already exists: ${nextTag}`)
  }
  if (manualTag && latestTag && !isGreaterVersionTag(parsedNextTag, latestTag)) {
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
