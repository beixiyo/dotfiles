import { REASONS } from './reasons.ts'
import { expandHome, isDangerousRmTarget, SENSITIVE } from './paths.ts'
import { cmdExec, exposeShellCommandBodies, segmentOf, SHELL_PATH, SHELLS, splitShellWords, stripQuoted } from './shell.ts'
import { GIT_WRITE_PATTERNS } from './git.ts'
import type { Ctx, Hit, HitLevel } from './types.ts'

/**
 * 正则引擎：剥引号后全文扫描命令起点，零运行时依赖
 *
 * 是 hook 的原始实现，也是 AST 引擎不可用时的兜底。已知边界（转义管道 / 单引号 $()
 * / heredoc 文本会误判 deny）由 AST 引擎修复，见 ast-engine.ts
 */

const DENY_PATTERNS: Array<{ re: RegExp; reason: string; raw?: boolean }> = [
  { re: cmdExec('shutdown', 'reboot', 'poweroff', 'halt'), reason: REASONS.shutdown },
  { re: cmdExec('service'), reason: REASONS.service },
  // 注意：Linux 无 `format` 命令（DOS/Windows 才有），删除以消除对 grep "a|format" 等的误杀
  { re: cmdExec('fdisk', 'mkfs', 'wipefs', 'sgdisk'), reason: REASONS.disk },

  // pipe 到 shell：| bash  | /bin/sh  | env bash
  // (?<!['"`]) 排除引号内的 | bash（如 grep '| bash' file）
  {
    re: new RegExp(`(?<!['"\`])\\|\\s*(?:env\\s+)?${SHELL_PATH}(?:${SHELLS})\\b`, 'g'),
    reason: REASONS.pipeShell,
  },
  // 进程替换执行远程脚本：bash <(curl ...)  source <(wget ...)
  {
    re: new RegExp(`(?:^|[;|&\`(\\n])\\s*(?:${SHELL_PATH}(?:${SHELLS})|\\.|source)\\s+<\\(`, 'g'),
    reason: REASONS.procSubst,
  },
  // eval 执行命令替换：eval "$(curl ...)"  eval $(wget ...)
  // raw: 双引号内的 $() 仍会真实执行，必须扫描原始命令而非剥离引号后的版本
  {
    re: /\beval\s+["'`]?\$\(/g,
    reason: REASONS.evalSubst,
    raw: true,
  },
]

// systemctl 写操作：子命令不在只读白名单内即视为写
//   (?:-\S+\s+)* 先吃掉全局选项（--user/--system/--no-pager 等），子命令未必紧跟 systemctl
//   末尾 [^-\s]\S* 要求子命令不以 - 开头：否则回溯会把 --user 当子命令匹配，绕过白名单
const SYSTEMCTL_WRITE =
  /\bsystemctl\s+(?:-\S+\s+)*(?!(?:status|show|list-\S*|is-active|is-enabled|is-failed|cat|help)\b)[^-\s]\S*/g

// 打印环境变量（可能含密钥）：只拦「会输出全量 env」的形态
//   放行无害用法：env VAR=x cmd（设环境跑命令）、export FOO=bar（赋值）、set -e/-o（shell 控制）
const ENV_DUMP_PATTERNS: Array<{ re: RegExp; reason: string }> = [
  { re: cmdExec('printenv'), reason: REASONS.envDump },
  { re: /(?:^|[;|&`(\n])\s*env(?:\s+-\S+)*\s*(?:$|[|;&\n>])/g, reason: REASONS.envDump },
  { re: /(?:^|[;|&`(\n])\s*export(?:\s+-p)?\s*(?:$|[|;&\n>])/g, reason: REASONS.exportDump },
  { re: /(?:^|[;|&`(\n])\s*set\s*(?:$|[|;&\n])/g, reason: REASONS.setDump },
]

export const collectHitsRegex = (ctx: Ctx): Hit[] => {
  const { cmd, cwd, isCodex } = ctx
  const hits: Hit[] = []

  // 剥离引号内文本后再扫描，避免引号内的正则/文本误触发命令规则
  const scan = stripQuoted(exposeShellCommandBodies(cmd))

  const collect = (level: HitLevel, re: RegExp, reason: string, target: string, codexAllow = false): void => {
    for (const m of target.matchAll(re)) {
      hits.push({ level, reason, segment: segmentOf(m, target, cmd), index: m.index ?? 0, codexAllow })
    }
  }

  // 取某个 rm 命中起点到下一个 shell 分隔符之间的参数区（用原始 cmd，含引号内，避免漏判引号目标），
  // 跳过命令名 / flag / 赋值前缀后，任一目标 token 命中危险判定即视为危险 rm
  const isDangerousRm = (start: number): boolean => {
    const rel = cmd.slice(start).search(/[;\n]|&&|\|\||\|/)
    const end = rel === -1 ? cmd.length : start + rel
    return splitShellWords(cmd.slice(start, end)).some(
      tok => !tok.startsWith('-')
        && !/^(?:rm|rmdir|sudo)$/.test(tok)
        && !tok.includes('=')
        && isDangerousRmTarget(tok, cwd),
    )
  }

  for (const { re, reason, raw } of DENY_PATTERNS) collect('deny', re, reason, raw ? cmd : scan)

  // rm/rmdir：普通目标两端都静默放行；只有危险目标才进入决策（Claude ask、Codex deny）
  for (const m of scan.matchAll(cmdExec('rm', 'rmdir'))) {
    const lead = m[0].match(/^[;|&`(\s\n]*/)?.[0].length ?? 0
    const start = (m.index ?? 0) + lead
    if (isDangerousRm(start)) {
      hits.push({ level: 'ask', reason: REASONS.rm, segment: segmentOf(m, scan, cmd), index: m.index ?? 0 })
    }
  }

  collect('ask', SYSTEMCTL_WRITE, REASONS.systemctl, scan)

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
        hits.push({ level: isCodex ? 'deny' : 'ask', reason, segment: tok.slice(0, 80), index: cmd.indexOf(raw) })
        break
      }
    }
  }

  for (const { re, reason } of ENV_DUMP_PATTERNS) collect('ask', re, reason, scan)

  return hits
}
