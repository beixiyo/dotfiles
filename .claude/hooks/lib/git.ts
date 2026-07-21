import { REASONS } from './reasons.ts'

// git 写/只读子命令判定（正则引擎与 AST 引擎共用）

const GIT_SUBCMDS = [
  'add', 'am', 'apply', 'bisect', 'branch', 'checkout', 'cherry-pick', 'clean', 'clone', 'commit',
  'config', 'fetch', 'gc', 'init', 'lfs', 'maintenance', 'merge', 'mv', 'notes', 'prune', 'pull',
  'push', 'rebase', 'remote', 'repack', 'replace', 'reset', 'restore', 'revert', 'rm',
  'sparse-checkout', 'stash', 'submodule', 'switch', 'tag', 'update-index', 'update-ref', 'worktree',
].join('|')

/**
 * git 只读子命令白名单：这些子命令不改动仓库/工作区，命中后从 git 写规则里剔除放行
 *
 * 仅收录明确只读的形态，宁可少放也不误放——带位置参数（如 `git branch foo` 建分支、
 * `git remote add x`）或写 flag（`branch -d`）的不在此列，会继续按写操作拦截
 */
const GIT_READONLY: RegExp[] = [
  /^git\s+(?:-C\s+\S+\s+)?stash\s+(?:list|show)\b/,
  /^git\s+(?:-C\s+\S+\s+)?branch\s*$/,
  /^git\s+(?:-C\s+\S+\s+)?branch\s+(?:-a|-r|-v|-vv|-l|--list|--all|--remotes|--show-current|--merged|--no-merged|--contains|--points-at)\b/,
  /^git\s+(?:-C\s+\S+\s+)?tag\s*$/,
  /^git\s+(?:-C\s+\S+\s+)?tag\s+(?:-l|--list|-n)\b/,
  /^git\s+(?:-C\s+\S+\s+)?remote\s*(?:-v|--verbose)?\s*$/,
  /^git\s+(?:-C\s+\S+\s+)?remote\s+(?:show|get-url)\b/,
  /^git\s+(?:-C\s+\S+\s+)?worktree\s+list\b/,
  /^git\s+(?:-C\s+\S+\s+)?submodule\s+(?:status|summary)\b/,
  /^git\s+(?:-C\s+\S+\s+)?config\s+(?:-l|--list|--get|--get-all|--get-regexp|--get-urlmatch|--show-origin|--show-scope)\b/,
  /^git\s+(?:-C\s+\S+\s+)?notes\s+(?:list|show)\b/,
  /^git\s+(?:-C\s+\S+\s+)?lfs\s+(?:env|ls-files|status)\b/,
]

export const isGitReadonly = (segment: string): boolean => GIT_READONLY.some(re => re.test(segment))

/** git 写操作（rm 已单独处理）——命中后 Codex 静默放行（codexAllow），Claude 仍 ask */
export const GIT_WRITE_PATTERNS: Array<{ re: RegExp; reason: string }> = [
  { re: new RegExp(`\\bgit\\s+(${GIT_SUBCMDS})\\b`, 'g'), reason: REASONS.gitWrite },
  { re: new RegExp(`\\bgit\\s+-C\\s+\\S+\\s+(${GIT_SUBCMDS})\\b`, 'g'), reason: REASONS.gitWriteC },
  { re: new RegExp(`\\bgit\\s+-\\S.*\\b(${GIT_SUBCMDS})\\b`, 'g'), reason: REASONS.gitWriteOpt },
]
