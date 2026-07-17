#!/usr/bin/env bun
import path from 'node:path'

/**
 * PreToolUse hook: 通用权限管控（Bash + Read）
 *
 * 统一管理 Claude Code / Codex 的工具权限：
 *   Bash — deny/ask 命令规则，全文扫描（不限前缀），防复合命令/flag 绕过
 *   Read — 敏感路径保护（.env / .ssh / .gnupg / .aws / .netrc）
 *
 * Codex ask 兼容性说明（最后验证：2026-07-18，codex-cli 0.144.5，仍未变）
 * - Claude Code 支持 PreToolUse 返回 permissionDecision: 'ask'，由客户端弹出审批
 * - Codex schema 能解析 'ask'，但运行时 output_parser 显式判其 unsupported（放行 + warning），
 *   PermissionRequest hook 也只有 allow/deny——即整个 hook 体系没有任何触发原生审批的路径
 * - 故 Codex 下无「弹审批」中间态，只有放行或硬 deny 二选一：
 *     · 危险命令（关机/磁盘/pipe-to-shell、systemctl 写、敏感文件读、env dump、危险 rm）→ 升级 deny 硬拦
 *     · git 写操作 → 静默放行；Claude Code 下则返回 ask 弹审批
 *     · 普通 rm/rmdir → 两端都静默放行；危险 rm/rmdir → Claude ask、Codex deny
 * - 本机 Codex 使用 approval_policy=never + danger-full-access。这里的「静默放行」就是 hook
 *   不输出决策并 exit 0，不存在后续审批或沙箱兜底
 *
 * rm 静态判定边界：
 * - 只展开路径开头的 ~、$HOME、${HOME}，并做引号分词与词法路径归一化
 * - 不执行 shell，也不求值其他变量、glob 或命令替换；命令替换目标按危险处理
 * - 其他变量（如 $TARGET）无法知道运行时值，按普通目标处理，这是刻意接受的边界
 *
 * 相关上游记录：
 * - openai/codex#28437（open）：Support PreToolUse permissionDecision: ask for native approval prompts（求这个功能，未做）
 * - openai/codex#25555（open）：Hook output schemas allow values later rejected by parser（schema 收但 parser 拒的机制）
 * - openai/codex#27833（open）：PreToolUse deny 对 apply_patch 不生效——文件写入类 deny 拦不住，本 hook 的防护对 Bash 才可靠
 * - openai/codex#20702 / #20756 / #26422（closed）：更早的 ask / schema 对齐请求，均未落地 ask 审批
 */

const input = await Bun.stdin.text()

let toolName = ''
let toolInput: Record<string, unknown> = {}
let isCodex = false
let cwd = process.cwd()

try {
  const data = JSON.parse(input)
  toolName = data?.tool_name ?? ''
  toolInput = data?.tool_input ?? {}
  isCodex = typeof data?.turn_id === 'string'
  cwd = typeof data?.cwd === 'string' && data.cwd ? data.cwd : cwd
}
catch {
  process.exit(0)
}

// ── 决策输出 ─────────────────────────────────────────────────

type PermissionDecision = 'deny' | 'ask'
type HookDecision = PermissionDecision | 'allow'
type HitLevel = PermissionDecision

/**
 * Codex 当前不支持 hook ask 审批：客户端不会弹审批，故 ask 级命中在 Codex 中升级为 deny（安全默认）
 */
const resolveDecision = (decision: PermissionDecision): HookDecision => {
  if (isCodex && decision === 'ask') return 'deny'

  return decision
}

/**
 * 发出最终决策。allow → 静默放行（exit 0）；deny/ask → 打印 PreToolUse 决策 JSON
 * hit 为命中的命令片段（可选），拼进 reason 方便在复合命令里定位被拦的那一段
 */
const emit = (resolved: HookDecision, reason: string, hit?: string): never => {
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

/**
 * 简单场景：把 ask/deny 经 resolveDecision（Codex 下 ask→deny）后发出
 * 用于 Read 路径与不涉及 git/rm 放行豁免的单点命中
 */
const finish = (decision: PermissionDecision, reason: string, hit?: string): never =>
  emit(resolveDecision(decision), reason, hit)

// ── 敏感文件规则（Read 与 Bash 共用）─────────────────────────
// 既拦 Read 工具直接读，也拦 Bash 里 cat/grep/cp/xxd/source/< 重定向 等迂回读取
const HOME = process.env.HOME ?? ''

/**
 * 把路径开头的 `~`、`$HOME` 或 `${HOME}` 统一成 HOME 绝对路径
 * 仅用于静态安全判定，不调用 shell，也不展开其他变量、glob 或命令替换
 */
const expandHome = (p: string): string => {
  if (p === '~') return HOME
  if (p.startsWith('~/')) return HOME + p.slice(1)

  return p
    .replace(/^\$\{HOME\}(?=\/|$)/, HOME)
    .replace(/^\$HOME(?=\/|$)/, HOME)
}

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
    // stripQuoted 会保留引号、把引号内容替换为空格，因此赋值值必须同时接受 "   " / '   '
    // 这也覆盖 PATH="$PWD/bin:$PATH" rm 这类常见前缀，避免带引号的环境赋值绕过命令起点判断
    const assignmentValue = `(?:"[^"]*"|'[^']*'|[^\\s"'])*`
    const assignment = `\\w+=${assignmentValue}\\s+`

    return new RegExp(`(?:^|[;|&\`(\\n])\\s*(?:${assignment})*(?:sudo\\s+(?:-\\S+\\s+)*)?(?:${escaped})\\b`, 'g')
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

  /**
   * 把字面量 shell -c 的命令体暴露给后续同一套扫描规则
   * wrapper 与引号位置替换为空格/分隔符并保持字符串长度，确保命中位置仍能映射回原命令
   */
  const exposeShellCommandBodies = (source: string): string => {
    const shell = `${SHELL_PATH}(?:${SHELLS})`
    const expose = (_match: string, prefix: string, body: string): string =>
      `${' '.repeat(prefix.length - 1)};${body} `

    return source
      .replace(new RegExp(`(${shell}\\s+-c\\s+")((?:\\\\.|[^"\\\\])*)"`, 'g'), expose)
      .replace(new RegExp(`(${shell}\\s+-c\\s+')([^']*)'`, 'g'), expose)
  }

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

  const isGitReadonly = (segment: string): boolean => GIT_READONLY.some(re => re.test(segment))

  // systemctl 写操作：子命令不在只读白名单内即视为写
  //   (?:-\S+\s+)* 先吃掉全局选项（--user/--system/--no-pager 等），子命令未必紧跟 systemctl
  //   末尾 [^-\s]\S* 要求子命令不以 - 开头：否则回溯会把 --user 当子命令匹配，绕过白名单
  const SYSTEMCTL_WRITE =
    /\bsystemctl\s+(?:-\S+\s+)*(?!(?:status|show|list-\S*|is-active|is-enabled|is-failed|cat|help)\b)[^-\s]\S*/g

  // git 写操作（rm 已单独处理，见下方危险判定）——Codex 下放行（codexAllow），Claude 仍 ask
  const GIT_WRITE_PATTERNS: Array<{ re: RegExp; reason: string }> = [
    { re: new RegExp(`\\bgit\\s+(${GIT_SUBCMDS})\\b`, 'g'), reason: 'git 写操作' },
    { re: new RegExp(`\\bgit\\s+-C\\s+\\S+\\s+(${GIT_SUBCMDS})\\b`, 'g'), reason: 'git -C 跨仓库写操作' },
    { re: new RegExp(`\\bgit\\s+-\\S.*\\b(${GIT_SUBCMDS})\\b`, 'g'), reason: 'git 带选项写操作' },
  ]

  // 这些目录树下的任意目标都视为危险；macOS 的 /etc、/var 实际落在 /private 下，显式覆盖两种写法
  const RM_PROTECTED_TREES = [
    '/bin', '/boot', '/dev', '/etc', '/lib', '/lib64', '/opt', '/proc', '/root', '/sbin', '/sys',
    '/usr', '/var', '/System', '/Library', '/Applications', '/private/etc', '/private/var',
  ]

  // 这些只是容器根：拒绝根本身及直接 glob，但不把 HOME、挂载盘或 /private/tmp 下的普通文件全部判危险
  const RM_PROTECTED_ROOTS = ['/private', '/Users', '/Volumes']

  const isDirectGlob = (candidate: string, root: string): boolean => {
    if (!candidate.startsWith(`${root}/`)) return false

    const relative = candidate.slice(root.length + 1)
    return !relative.includes('/') && /[*?\[\]{}]/.test(relative)
  }

  const isWithin = (candidate: string, root: string): boolean =>
    candidate === root || candidate.startsWith(`${root}/`)

  /**
   * 按 shell 引号规则拆出参数，保留引号内空格并拼接相邻片段
   * 这里只做静态安全分类，不执行变量、命令替换或 glob
   */
  const splitShellWords = (input: string): string[] => {
    const words: string[] = []
    let current = ''
    let quote: '"' | '\'' | null = null

    const flush = (): void => {
      if (current === '') return
      words.push(current)
      current = ''
    }

    for (let i = 0; i < input.length; i++) {
      const char = input[i]

      if (char === '\\' && quote !== '\'') {
        current += input[i + 1] ?? ''
        i++
        continue
      }

      if (quote !== null) {
        if (char === quote) quote = null
        else current += char
        continue
      }

      if (char === '"' || char === '\'') {
        quote = char
        continue
      }

      if (/\s/.test(char)) {
        flush()
        continue
      }

      current += char
    }

    flush()
    return words
  }

  const isDangerousRmTarget = (token: string): boolean => {
    if (token === '') return false

    // 动态命令替换无法静态确认最终目标，按危险处理
    if (/`|\$\(/.test(token)) return true

    const expanded = expandHome(token)

    // 删除前先按 cwd 做词法归一化，堵住 ~/.config/..、$HOME/.、foo/.. 等等价写法
    const normalized = path.resolve(cwd, expanded).replace(/\/+$/, '') || '/'

    // 根 / 当前或上级目录整体 / 家目录（含变量、引号和父目录折叠后的等价形式）
    if (normalized === '/' || normalized === cwd || normalized === path.dirname(cwd)) return true
    // .git 目录（呼应「递归删除曾删光含 .git 的项目」教训）
    if (/(?:^|\/)\.git(?:\/|$)/.test(expanded)) return true
    if (RM_PROTECTED_TREES.some(root => isWithin(normalized, root))) return true
    if (RM_PROTECTED_ROOTS.some(root => normalized === root || isDirectGlob(normalized, root))) return true

    if (HOME && (normalized === HOME || isDirectGlob(normalized, HOME))) return true

    return false
  }

  // 取某个 rm 命中起点到下一个 shell 分隔符之间的参数区（用原始 cmd，含引号内，避免漏判引号目标），
  // 跳过命令名 / flag / 赋值前缀后，任一目标 token 命中危险判定即视为危险 rm
  const isDangerousRm = (start: number): boolean => {
    const rel = cmd.slice(start).search(/[;\n]|&&|\|\||\|/)
    const end = rel === -1 ? cmd.length : start + rel
    const tokens = splitShellWords(cmd.slice(start, end))
    return tokens.some(
      tok => !tok.startsWith('-')
        && !/^(?:rm|rmdir|sudo)$/.test(tok)
        && !tok.includes('=')
        && isDangerousRmTarget(tok),
    )
  }

  // 剥离引号内文本后再扫描，避免引号内的正则/文本误触发命令规则
  const scan = stripQuoted(exposeShellCommandBodies(cmd))

  // 收集全部命中（不再命中即退出），让复合命令里每一段被拦的子命令都能呈现
  //   codexAllow：该 ask 命中在 Codex 下是否静默放行；当前只用于用户明确允许的 git 写操作
  const hits: Array<{ level: HitLevel; reason: string; segment: string; index: number; codexAllow?: boolean }> = []

  const collect = (level: HitLevel, re: RegExp, reason: string, target: string, codexAllow = false): void => {
    for (const m of target.matchAll(re)) {
      hits.push({ level, reason, segment: segmentOf(m, target), index: m.index ?? 0, codexAllow })
    }
  }

  for (const { re, reason, raw } of DENY_PATTERNS) collect('deny', re, reason, raw ? cmd : scan)

  // rm/rmdir：普通目标两端都静默放行；只有危险目标才进入决策（Claude ask、Codex deny）
  for (const m of scan.matchAll(cmdExec('rm', 'rmdir'))) {
    const lead = m[0].match(/^[;|&`(\s\n]*/)?.[0].length ?? 0
    const start = (m.index ?? 0) + lead
    const dangerous = isDangerousRm(start)
    if (dangerous) {
      hits.push({
        level: 'ask',
        reason: '危险文件删除（根 / 家目录 / 系统目录 / .git）',
        segment: segmentOf(m, scan),
        index: m.index ?? 0,
      })
    }
  }

  collect('ask', SYSTEMCTL_WRITE, 'systemctl 写操作', scan)

  for (const { re, reason } of GIT_WRITE_PATTERNS) collect('ask', re, reason, scan, true)

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

    // 决策：任一 deny 级命中 → 整条拦死。否则 Claude Code 走 ask（弹审批）。
    //   Codex 无审批弹窗：仅当全部 ask 命中都标 codexAllow（git 写）才静默放行；
    //   一旦混入非 codexAllow 的 ask（systemctl / 敏感读 / env dump / 危险 rm）则整条 deny
    const resolved: HookDecision = effectiveHits.some(h => h.level === 'deny')
      ? 'deny'
      : isCodex
        ? (effectiveHits.every(h => h.codexAllow) ? 'allow' : 'deny')
        : 'ask'

    emit(resolved, lines.join('\n'))
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
