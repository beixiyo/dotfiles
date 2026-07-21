// 通用 shell 文本工具：分词、引号剥离、命令起点定位、shell -c 展开（无策略，纯解析）

// 支持的危险 shell 列表（pipe / 进程替换 / eval 共用）
export const SHELLS = 'sh|bash|zsh|fish|dash|ksh|csh|tcsh|ash|pwsh|powershell'

// 可选的绝对路径前缀：/bin/  /usr/bin/  /usr/local/bin/
export const SHELL_PATH = `(?:/(?:usr(?:/local)?/)?bin/)?`

// sudo/doas 中会消费下一个 token 的选项。长选项使用 `--name=value` 时不消费下一项
const PRIVILEGE_ARG_SHORT = 'C|D|g|h|p|R|r|t|T|u|a'
const PRIVILEGE_ARG_LONG = [
  'close-from', 'chdir', 'group', 'host', 'prompt', 'chroot', 'role', 'type',
  'command-timeout', 'user', 'auth-style', 'config',
].join('|')

// 跳过 sudo/doas 包装器及其选项，最终停在真正的命令名之前
const PRIVILEGE_PREFIX = `(?:sudo|doas)\\s+(?:(?:-(?:${PRIVILEGE_ARG_SHORT})|--(?:${PRIVILEGE_ARG_LONG}))\\s+\\S+\\s+|--(?:${PRIVILEGE_ARG_LONG})=\\S+\\s+|-\\S+\\s+|--\\s+)*`

/**
 * 剥离引号内文本：把单/双引号内的字符替换为空格，保留引号本身与引号外结构
 *
 * 目的：避免引号内的正则/文本被当成 shell 结构误判
 *   如 grep "a|format|b" 的 `|` 是正则"或"，不是管道
 * 注意：双引号内的命令替换 $() 仍会真实执行，故 eval 规则需用原始命令扫描（见 raw 标记）
 */
export const stripQuoted = (s: string): string => {
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
 * 按 shell 引号规则拆出参数，保留引号内空格并拼接相邻片段
 * 这里只做静态安全分类，不执行变量、命令替换或 glob
 */
export const splitShellWords = (input: string): string[] => {
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

/**
 * 生成"命令起点"正则：只匹配作为可执行单元出现的命令名
 *
 * 匹配位置：行首 | 分隔符（; && || | 换行 $( ）之后
 * 容错前缀：环境变量赋值（X=1）、sudo/doas 及其选项，防前缀绕过
 * 不匹配：作为参数出现的同名单词（如 grep shutdown、jq '.format'）
 */
export const cmdExec = (...names: string[]): RegExp => {
  const escaped = names.map(n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')
  // stripQuoted 会保留引号、把引号内容替换为空格，因此赋值值必须同时接受 "   " / '   '
  // 这也覆盖 PATH="$PWD/bin:$PATH" rm 这类常见前缀，避免带引号的环境赋值绕过命令起点判断
  const assignmentValue = `(?:"[^"]*"|'[^']*'|[^\\s"'])*`
  const assignment = `\\w+=${assignmentValue}\\s+`

  return new RegExp(`(?:^|[;|&\`(\\n])\\s*(?:${assignment})*(?:${PRIVILEGE_PREFIX})?(?:${escaped})\\b`, 'g')
}

/**
 * 从命中位置切出「命中的子命令片段」，方便在复合命令里定位是哪一段被拦
 *
 * 借助 stripQuoted 的长度对齐：用扫描串上的 match.index 回到原始 cmd 取真实文本
 *   - 去掉 cmdExec 匹配带进来的前导分隔符/空白
 *   - 向后截到下一个 shell 分隔符（; 换行 && || |），即一条子命令的边界
 */
export const segmentOf = (m: RegExpMatchArray, scanned: string, cmd: string): string => {
  const lead = m[0].match(/^[;|&\`(\s\n]*/)?.[0].length ?? 0
  const start = (m.index ?? 0) + lead
  const rel = scanned.slice(start).search(/[;\n]|&&|\|\||\|/)
  const end = rel === -1 ? cmd.length : start + rel
  return cmd.slice(start, end).trim().slice(0, 80)
}

/**
 * 把字面量 shell -c 的命令体暴露给后续同一套扫描规则
 * wrapper 与引号位置替换为空格/分隔符并保持字符串长度，确保命中位置仍能映射回原命令
 */
export const exposeShellCommandBodies = (source: string): string => {
  const shell = `${SHELL_PATH}(?:${SHELLS})`
  const expose = (_match: string, prefix: string, body: string): string =>
    `${' '.repeat(prefix.length - 1)};${body} `

  return source
    .replace(new RegExp(`(${shell}\\s+-c\\s+")((?:\\\\.|[^"\\\\])*)"`, 'g'), expose)
    .replace(new RegExp(`(${shell}\\s+-c\\s+')([^']*)'`, 'g'), expose)
}
