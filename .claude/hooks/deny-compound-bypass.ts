#!/usr/bin/env bun
/**
 * PreToolUse hook: 通用权限管控（Bash + Read）
 *
 * 统一管理 Claude Code / Codex 的工具权限：
 *   Bash — deny/ask 命令规则，全文扫描（不限前缀），防复合命令/flag 绕过
 *   Read — 敏感路径保护（.env / .ssh / .gnupg / .aws / .netrc）
 *
 * Codex ask 兼容性说明（最后验证：2026-06-22，codex-cli 0.141.0）
 * - Claude Code 支持 PreToolUse 返回 permissionDecision: 'ask'，由客户端弹出审批
 * - Codex 当前 schema 能解析 'ask'，但运行时不支持把它路由到原生审批
 * - 本机实测：当前 Codex TUI 会话中，PreToolUse hook 确实执行并输出 'ask'，
 *   但 Bash 命令继续执行，没有出现审批弹窗
 * - 因此本脚本对 Codex 仅保留 deny 级硬拦截；ask 级命中直接放行，避免把正常排查命令变成硬拒绝
 *
 * 相关上游记录：
 * - openai/codex#28437（open）：Support PreToolUse permissionDecision: ask for native approval prompts
 * - openai/codex#25555（open）：Hook output schemas allow values later rejected by parser
 * - openai/codex#20702（closed）：Support PreToolUse permissionDecision ask
 * - openai/codex#20756（closed）：support PreToolUse allow and ask permissionDecision
 * - openai/codex#26422（closed）：[codex] Align hook output schemas with runtime
 */

const input = await Bun.stdin.text()

let toolName = ''
let toolInput: Record<string, unknown> = {}
let isCodex = false

try {
  const data = JSON.parse(input)
  toolName = data?.tool_name ?? ''
  toolInput = data?.tool_input ?? {}
  isCodex = typeof data?.turn_id === 'string'
    || 'agent_id' in data
    || 'agent_type' in data
}
catch {
  process.exit(0)
}

// ── 决策输出 ─────────────────────────────────────────────────

type PermissionDecision = 'deny' | 'ask'
type HookDecision = PermissionDecision | 'allow'
type HitLevel = PermissionDecision

/**
 * Codex 当前不支持 hook ask 审批：ask 级规则在 Codex 中视为 allow
 * 真正需要硬拦的规则必须在收集命中时标记为 deny
 */
const resolveDecision = (decision: PermissionDecision): HookDecision => {
  if (isCodex && decision === 'ask') return 'allow'

  return decision
}

/**
 * 结束 hook。hit 为命中的命令片段（可选），拼进 reason 方便在复合命令里定位被拦的那一段
 */
const finish = (decision: PermissionDecision, reason: string, hit?: string): never => {
  const resolved = resolveDecision(decision)
  if (resolved === 'allow') process.exit(0)

  const detail = hit ? `${reason}｜命中：${hit}` : reason

  console.log(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: resolved,
      permissionDecisionReason: detail,
    },
  }))

  process.exit(0)
}

// ── 敏感文件规则（Read 与 Bash 共用）─────────────────────────
// 既拦 Read 工具直接读，也拦 Bash 里 cat/grep/cp/xxd/source/< 重定向 等迂回读取
const HOME = process.env.HOME ?? ''

const expandHome = (p: string): string => p.startsWith('~/') ? HOME + p.slice(1) : p

/**
 * 敏感路径匹配器：对「规范化后的路径」逐条 test
 *
 * 用 (^|/) 锚定路径段起点，兼容绝对路径、~ 展开后路径、以及相对路径（如 .ssh/id_rsa）
 * .env 段尾用 (?!.*example) 放行 .env.example，与原 Read 规则一致
 */
const SENSITIVE: Array<{ re: RegExp; reason: string }> = [
  { re: /(^|\/)\.[^/]*env(?!.*example)[^/]*$/i, reason: '访问 .env 敏感文件' },
  { re: /(^|\/)\.ssh(\/|$)/i, reason: '访问 .ssh 凭据' },
  { re: /(^|\/)\.gnupg(\/|$)/i, reason: '访问 .gnupg 密钥' },
  { re: /(^|\/)\.aws(\/|$)/i, reason: '访问 .aws 凭据' },
  { re: /(^|\/)\.netrc$/i, reason: '访问 .netrc' },
]

// ═══════════════════════════════════════════════════════════════
// Bash 规则
// ═══════════════════════════════════════════════════════════════

if (toolName === 'Bash') {
  const cmd = (toolInput.command as string) ?? ''
  if (!cmd) process.exit(0)

  /**
   * 剥离引号内文本：把单/双引号内的字符替换为空格，保留引号本身与引号外结构
   *
   * 目的：避免引号内的正则/文本被当成 shell 结构误判
   *   如 grep "a|format|b" 的 `|` 是正则"或"，不是管道
   * 注意：双引号内的命令替换 $() 仍会真实执行，故 eval 规则需用原始命令扫描（见 raw 标记）
   */
  const stripQuoted = (s: string): string => {
    let out = ''
    let quote: '"' | '\'' | null = null

    for (let i = 0; i < s.length; i++) {
      const c = s[i]

      if (quote === null) {
        if (c === '\\') {
          out += c + (s[i + 1] ?? '')
          i++
          continue
        }
        if (c === '"' || c === '\'') {
          quote = c
          out += c
          continue
        }
        out += c
        continue
      }

      if (c === quote) {
        quote = null
        out += c
        continue
      }

      // ⚠️ shell 中只有「双引号」内的 \ 是转义符：\" 是字面引号、不结束引号，
      //    故需吃掉 \ 和它转义的下一个字符，否则那个 " 会被下一行误判为引号结束
      //    「单引号」内 \ 是普通字面字符，唯一能结束单引号的只有下一个 '，
      //    所以单引号不做（也绝不能做）转义跳过，直接落到下面 out += ' ' 当普通字符
      if (quote === '"' && c === '\\') {
        out += '  '
        i++
        continue
      }

      out += ' '
    }

    return out
  }

  /**
   * 生成"命令起点"正则：只匹配作为可执行单元出现的命令名
   *
   * 匹配位置：行首 | 分隔符（; && || | 换行 $( ）之后
   * 容错前缀：环境变量赋值（X=1）、sudo 及其选项（sudo -i），防前缀绕过
   * 不匹配：作为参数出现的同名单词（如 grep shutdown、jq '.format'）
   */
  const cmdExec = (...names: string[]): RegExp => {
    const escaped = names.map(n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')
    return new RegExp(`(?:^|[;|&\`(\\n])\\s*(?:\\w+=\\S*\\s+)*(?:sudo\\s+(?:-\\S+\\s+)*)?(?:${escaped})\\b`, 'g')
  }

  /**
   * 从命中位置切出「命中的子命令片段」，方便在复合命令里定位是哪一段被拦
   *
   * 借助 stripQuoted 的长度对齐：用扫描串上的 match.index 回到原始 cmd 取真实文本
   *   - 去掉 cmdExec 匹配带进来的前导分隔符/空白
   *   - 向后截到下一个 shell 分隔符（; 换行 && || |），即一条子命令的边界
   */
  const segmentOf = (m: RegExpMatchArray, scanned: string): string => {
    const lead = m[0].match(/^[;|&\`(\s\n]*/)?.[0].length ?? 0
    const start = (m.index ?? 0) + lead
    const rel = scanned.slice(start).search(/[;\n]|&&|\|\||\|/)
    const end = rel === -1 ? cmd.length : start + rel
    return cmd.slice(start, end).trim().slice(0, 80)
  }

  // 支持的危险 shell 列表（pipe / 进程替换 / eval 共用）
  const SHELLS = 'sh|bash|zsh|fish|dash|ksh|csh|tcsh|ash|pwsh|powershell'

  // 可选的绝对路径前缀：/bin/  /usr/bin/  /usr/local/bin/
  const SHELL_PATH = `(?:/(?:usr(?:/local)?/)?bin/)?`

  const DENY_PATTERNS: Array<{ re: RegExp; reason: string; raw?: boolean }> = [
    { re: cmdExec('shutdown', 'reboot', 'poweroff', 'halt'), reason: '系统关机/重启命令' },
    { re: cmdExec('service'), reason: '系统服务控制命令' },
    // 注意：Linux 无 `format` 命令（DOS/Windows 才有），删除以消除对 grep "a|format" 等的误杀
    { re: cmdExec('fdisk', 'mkfs', 'wipefs', 'sgdisk'), reason: '磁盘格式化/分区命令' },

    // pipe 到 shell：| bash  | /bin/sh  | env bash
    // (?<!['"`]) 排除引号内的 | bash（如 grep '| bash' file）
    {
      re: new RegExp(`(?<!['"\`])\\|\\s*(?:env\\s+)?${SHELL_PATH}(?:${SHELLS})\\b`, 'g'),
      reason: 'pipe 到 shell',
    },
    // 进程替换执行远程脚本：bash <(curl ...)  source <(wget ...)
    {
      re: new RegExp(`(?:^|[;|&\`(\\n])\\s*(?:${SHELL_PATH}(?:${SHELLS})|\\.|source)\\s+<\\(`, 'g'),
      reason: '进程替换执行脚本',
    },
    // eval 执行命令替换：eval "$(curl ...)"  eval $(wget ...)
    // raw: 双引号内的 $() 仍会真实执行，必须扫描原始命令而非剥离引号后的版本
    {
      re: /\beval\s+["'`]?\$\(/g,
      reason: 'eval 执行命令替换',
      raw: true,
    },
  ]

  const GIT_SUBCMDS =
    'add|commit|push|pull|fetch|merge|rebase|reset|checkout|switch|branch|tag|stash|clean|am|apply|cherry-pick|revert|remote|submodule|worktree|update-index|update-ref'

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
  ]

  const isGitReadonly = (segment: string): boolean => GIT_READONLY.some(re => re.test(segment))

  // systemctl 写操作：子命令不在只读白名单内即视为写
  //   (?:-\S+\s+)* 先吃掉全局选项（--user/--system/--no-pager 等），子命令未必紧跟 systemctl
  //   末尾 [^-\s]\S* 要求子命令不以 - 开头：否则回溯会把 --user 当子命令匹配，绕过白名单
  const SYSTEMCTL_WRITE =
    /\bsystemctl\s+(?:-\S+\s+)*(?!(?:status|show|list-\S*|is-active|is-enabled|is-failed|cat|help)\b)[^-\s]\S*/g

  const ASK_PATTERNS: Array<{ re: RegExp; reason: string }> = [
    { re: cmdExec('rm', 'rmdir'), reason: '危险文件删除' },
    { re: new RegExp(`\\bgit\\s+(${GIT_SUBCMDS})\\b`, 'g'), reason: 'git 写操作' },
    { re: new RegExp(`\\bgit\\s+-C\\s+\\S+\\s+(${GIT_SUBCMDS})\\b`, 'g'), reason: 'git -C 跨仓库写操作' },
    { re: new RegExp(`\\bgit\\s+-\\S.*\\b(${GIT_SUBCMDS})\\b`, 'g'), reason: 'git 带选项写操作' },
  ]

  // 剥离引号内文本后再扫描，避免引号内的正则/文本误触发命令规则
  const scan = stripQuoted(cmd)

  // 收集全部命中（不再命中即退出），让复合命令里每一段被拦的子命令都能呈现
  const hits: Array<{ level: HitLevel; reason: string; segment: string; index: number }> = []

  const collect = (level: HitLevel, re: RegExp, reason: string, target: string): void => {
    for (const m of target.matchAll(re)) {
      hits.push({ level, reason, segment: segmentOf(m, target), index: m.index ?? 0 })
    }
  }

  for (const { re, reason, raw } of DENY_PATTERNS) collect('deny', re, reason, raw ? cmd : scan)

  collect('ask', SYSTEMCTL_WRITE, 'systemctl 写操作', scan)

  for (const { re, reason } of ASK_PATTERNS) collect('ask', re, reason, scan)

  // 敏感文件迂回读取：cat/less/grep/cp/xxd/strings/source/< 重定向 等任意命令引用敏感路径
  //   不枚举读命令（枚举必有遗漏），改为扫描命令里出现的「敏感文件 token」，命中即 ask
  //   用「原始 cmd」切 token（含引号内，故能拦 cat ".env"；stripQuoted 会清空引号内反而漏拦）：
  //     把 shell 操作符与 = 替换为空白 → 按空白切 → 逐个剥外层引号 → 展开 ~/ → 匹配
  const fileTokens = cmd.replace(/[<>|&;()`=]/g, ' ').split(/\s+/).filter(Boolean)

  for (const raw of fileTokens) {
    const tok = raw.replace(/^['"]+/, '').replace(/['"]+$/, '')
    const norm = expandHome(tok)

    for (const { re, reason } of SENSITIVE) {
      if (re.test(norm)) {
        const level: HitLevel = isCodex ? 'deny' : 'ask'
        hits.push({ level, reason, segment: tok.slice(0, 80), index: cmd.indexOf(raw) })
        break
      }
    }
  }

  // 打印环境变量（可能含密钥）：只拦「会输出全量 env」的形态
  //   放行无害用法：env VAR=x cmd（设环境跑命令）、export FOO=bar（赋值）、set -e/-o（shell 控制）
  const ENV_DUMP_PATTERNS: Array<{ re: RegExp; reason: string }> = [
    // printenv：本职就是打印环境变量
    { re: cmdExec('printenv'), reason: '打印环境变量' },
    // env 后无命令可执行（裸 env / 仅带 flag / 接管道重定向）→ 打印全量 env
    { re: /(?:^|[;|&`(\n])\s*env(?:\s+-\S+)*\s*(?:$|[|;&\n>])/g, reason: '打印环境变量' },
    // export -p / 裸 export：列出全部导出变量
    { re: /(?:^|[;|&`(\n])\s*export(?:\s+-p)?\s*(?:$|[|;&\n>])/g, reason: '打印导出变量' },
    // 裸 set：bash 下列出全部变量与函数（放行 set -e / set -o pipefail 等）
    { re: /(?:^|[;|&`(\n])\s*set\s*(?:$|[|;&\n])/g, reason: '打印全部 shell 变量' },
  ]

  for (const { re, reason } of ENV_DUMP_PATTERNS) collect('ask', re, reason, scan)

  // git 写规则里剔除只读子命令（git stash list / git branch / git remote -v 等）
  const effectiveHits = hits.filter(
    h => !(h.reason.startsWith('git') && isGitReadonly(h.segment)),
  )

  if (effectiveHits.length > 0) {
    // 按在命令中出现的位置排序，并对相同「原因+片段」去重
    effectiveHits.sort((a, b) => a.index - b.index)

    // 按「子命令片段」去重：同一段命令被多条规则命中时只保留首条（排序后即出现位置在前、规则更具体的那条）
    const seen = new Set<string>()
    const lines = effectiveHits
      .filter(({ segment }) => {
        if (seen.has(segment)) return false
        seen.add(segment)
        return true
      })
      .map(({ reason, segment }) => `${reason}｜命中：${segment}`)

    // 任一 deny 级命中 → 整条命令拦死；否则走 ask。Codex 中 ask 会在 finish() 里放行
    const decision = effectiveHits.some(h => h.level === 'deny') ? 'deny' : 'ask'
    finish(decision, lines.join('\n'))
  }
}

// ═══════════════════════════════════════════════════════════════
// Read 规则：敏感路径保护
// ═══════════════════════════════════════════════════════════════

if (toolName === 'Read') {
  const filePath = (toolInput.file_path as string) ?? ''
  if (!filePath) process.exit(0)

  const normalized = expandHome(filePath)

  for (const { re, reason } of SENSITIVE) if (re.test(normalized)) finish(isCodex ? 'deny' : 'ask', reason, normalized)
}
