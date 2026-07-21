import { REASONS } from './reasons.ts'
import { expandHome, isDangerousRmTarget, SENSITIVE } from './paths.ts'
import { splitShellWords } from './shell.ts'
import { GIT_WRITE_PATTERNS, isGitReadonly } from './git.ts'
import type { Ctx, Hit, HitLevel } from './types.ts'

// tree-sitter 节点类型：仅本模块（AST 引擎）需要，不放进共享的 types.ts，
// 免得正则版可达图里出现 web-tree-sitter 引用
type TsNode = import('web-tree-sitter').Node
type TsTree = import('web-tree-sitter').Tree

/**
 * AST 引擎：tree-sitter-bash 解析成结构，白名单式判定，天生免疫复合/引号/转义绕过
 *
 * 依赖 web-tree-sitter + tree-sitter-wasms（本目录需 bun install）。这是唯一引入该依赖的
 * 模块，且为动态 import——不用 AST 的人不 import 本文件即可，正则引擎与之零耦合。
 *
 * 返回 null 表示解析不可用（缺 wasm / 解析报错 / 命令过长），调用方应回退正则（fail-closed）
 */
export const collectHitsAst = async (ctx: Ctx): Promise<Hit[] | null> => {
  const { cmd, cwd, isCodex } = ctx
  if (cmd.length > 20000) return null

  let parser: { parse: (s: string) => TsTree | null }
  try {
    const { createRequire } = await import('node:module')
    const require = createRequire(import.meta.url)
    const { Parser, Language } = await import('web-tree-sitter')
    await Parser.init()
    const lang = await Language.load(require.resolve('tree-sitter-wasms/out/tree-sitter-bash.wasm'))
    const p = new Parser()
    p.setLanguage(lang)
    parser = p
  }
  catch {
    return null
  }

  const SHELL_NAMES = new Set(['sh', 'bash', 'zsh', 'fish', 'dash', 'ksh', 'csh', 'tcsh', 'ash', 'pwsh', 'powershell'])
  const SHUTDOWN = new Set(['shutdown', 'reboot', 'poweroff', 'halt'])
  const SYSTEMCTL_RO = new Set(['status', 'show', 'is-active', 'is-enabled', 'is-failed', 'cat', 'help'])
  const DISK_RE = /^(?:fdisk|mkfs(?:\.\w+)?|wipefs|sgdisk)$/
  const PRIVILEGE_ARG_SHORT = new Set(['-C', '-D', '-g', '-h', '-p', '-R', '-r', '-t', '-T', '-u', '-a'])
  const PRIVILEGE_ARG_LONG = new Set([
    '--close-from', '--chdir', '--group', '--host', '--prompt', '--chroot', '--role', '--type',
    '--command-timeout', '--user', '--auth-style', '--config',
  ])

  const hits: Hit[] = []

  const seg = (t: string): string => t.trim().slice(0, 80)
  const base = (s: string): string => s.replace(/^.*\//, '')
  const unquote = (s: string): string => s.replace(/^['"]/, '').replace(/['"]$/, '')

  const nameOf = (command: TsNode): string =>
    command.namedChildren.find(c => c?.type === 'command_name')?.text ?? ''

  // command 的参数节点：排除命令名与前置 env 赋值
  const argsOf = (command: TsNode): TsNode[] =>
    command.namedChildren.filter((c): c is TsNode => !!c && c.type !== 'command_name' && c.type !== 'variable_assignment')

  // 剥掉 sudo/doas 及其选项，得到真正被执行的命令名与其参数
  const peel = (name: string, args: TsNode[]): { name: string; args: TsNode[] } => {
    if (name !== 'sudo' && name !== 'doas') return { name, args }

    let i = 0
    while (i < args.length) {
      const option = args[i].text
      if (option === '--') {
        i++
        break
      }
      if (!option.startsWith('-')) break

      const consumesNext = PRIVILEGE_ARG_SHORT.has(option) || PRIVILEGE_ARG_LONG.has(option)
      i += consumesNext ? 2 : 1
    }

    return i >= args.length ? { name: '', args: [] } : { name: base(args[i].text), args: args.slice(i + 1) }
  }

  // 复用 paths 的危险 rm 判定，喂给它单条命令节点的文本（内部无分隔符）
  const isDangerousRmText = (text: string): boolean =>
    splitShellWords(text).some(tok =>
      !tok.startsWith('-') && !/^(?:rm|rmdir|sudo)$/.test(tok) && !tok.includes('=') && isDangerousRmTarget(tok, cwd))

  const scanSensitive = (node: TsNode, offset: number): void => {
    const lit = expandHome(unquote(node.text))
    for (const { re, reason } of SENSITIVE) {
      if (re.test(lit)) {
        hits.push({ level: isCodex ? 'deny' : 'ask', reason, segment: seg(unquote(node.text)), index: node.startIndex + offset })
        break
      }
    }
  }

  const isShellStage = (command: TsNode): boolean => {
    const n = base(nameOf(command))
    if (SHELL_NAMES.has(n)) return true
    if (n === 'env') {
      const first = argsOf(command).find(a => !a.text.startsWith('-'))
      return !!first && SHELL_NAMES.has(base(first.text))
    }
    return false
  }

  const classifyCommand = (command: TsNode, offset: number, depth: number): void => {
    const rawArgs = argsOf(command)
    const { name, args } = peel(base(nameOf(command)), rawArgs)
    const index = command.startIndex + offset
    const push = (level: HitLevel, reason: string, codexAllow = false): void =>
      void hits.push({ level, reason, segment: seg(command.text), index, codexAllow })

    if (SHUTDOWN.has(name)) push('deny', REASONS.shutdown)
    else if (name === 'service') push('deny', REASONS.service)
    else if (DISK_RE.test(name)) push('deny', REASONS.disk)

    // shell -c "..."：命令体在字符串里，tree-sitter 不解析，需取出重新解析
    if (SHELL_NAMES.has(name) && depth < 3) {
      const ci = args.findIndex(a => a.text === '-c')
      const body = ci >= 0 ? args[ci + 1] : undefined
      if (body && (body.type === 'string' || body.type === 'raw_string')) {
        analyzeSource(unquote(body.text), index, depth + 1)
      }
    }

    // 进程替换执行脚本：bash <(curl ...) / source <(...)
    if ((SHELL_NAMES.has(name) || name === '.' || name === 'source') && rawArgs.some(a => a.type === 'process_substitution')) {
      push('deny', REASONS.procSubst)
    }

    // eval 执行命令替换（含单引号内的 $()——eval 会二次求值，故按文本判定）
    if (name === 'eval' && args.some(a => /\$\(|`/.test(a.text))) push('deny', REASONS.evalSubst)

    if (name === 'rm' || name === 'rmdir') {
      if (isDangerousRmText(command.text)) push('ask', REASONS.rm)
    }

    if (name === 'systemctl') {
      const sub = args.find(a => !a.text.startsWith('-'))?.text ?? ''
      if (sub && !SYSTEMCTL_RO.has(sub) && !sub.startsWith('list-')) push('ask', REASONS.systemctl)
    }

    if (name === 'git') {
      for (const { re, reason } of GIT_WRITE_PATTERNS) {
        re.lastIndex = 0
        if (re.test(command.text) && !isGitReadonly(command.text)) {
          push('ask', reason, true)
          break
        }
      }
    }

    // 环境变量全量打印：只拦「后面没有可执行命令」的形态
    if (name === 'printenv') push('ask', REASONS.envDump)
    else if (name === 'env' && !args.some(a => !a.text.startsWith('-'))) push('ask', REASONS.envDump)
    else if (name === 'set' && args.length === 0) push('ask', REASONS.setDump)

    for (const a of rawArgs) scanSensitive(a, offset)
  }

  const classifyDeclaration = (node: TsNode, offset: number): void => {
    if (!/^export\b/.test(node.text)) return
    const hasAssign = node.namedChildren.some(c => c?.type === 'variable_assignment')
    const hasNonFlag = node.namedChildren.some(c => c?.type === 'word' && !c.text.startsWith('-'))
    if (!hasAssign && !hasNonFlag) {
      hits.push({ level: 'ask', reason: REASONS.exportDump, segment: seg(node.text), index: node.startIndex + offset })
    }
  }

  const detectPipeToShell = (pipeline: TsNode, offset: number): void => {
    const stages = pipeline.namedChildren.filter((c): c is TsNode => !!c && (c.type === 'command' || c.type === 'redirected_statement'))
    for (let i = 1; i < stages.length; i++) {
      const stage = stages[i]
      const command = stage.type === 'redirected_statement'
        ? stage.namedChildren.find(c => c?.type === 'command') ?? null
        : stage
      if (command && isShellStage(command)) {
        hits.push({ level: 'deny', reason: REASONS.pipeShell, segment: seg(command.text), index: command.startIndex + offset })
      }
    }
  }

  const walk = (node: TsNode, offset: number, depth: number): void => {
    const t = node.type
    if (t === 'pipeline') detectPipeToShell(node, offset)
    if (t === 'command') classifyCommand(node, offset, depth)
    else if (t === 'declaration_command') classifyDeclaration(node, offset)
    else if (t === 'file_redirect') for (const c of node.namedChildren) if (c) scanSensitive(c, offset)

    for (const c of node.namedChildren) if (c) walk(c, offset, depth)
  }

  const analyzeSource = (src: string, offset: number, depth: number): void => {
    let tree: TsTree | null = null
    try {
      tree = parser.parse(src)
    }
    catch {
      return
    }
    if (tree) {
      walk(tree.rootNode, offset, depth)
      tree.delete()
    }
  }

  let root: TsNode
  let tree: TsTree | null = null
  try {
    tree = parser.parse(cmd)
    if (!tree) return null
    root = tree.rootNode
  }
  catch {
    return null
  }

  // 解析有语法错误 → 不冒险，回退正则（即现有生产行为）
  if (root.hasError) {
    tree.delete()
    return null
  }

  walk(root, 0, 0)
  tree.delete()
  return hits
}
