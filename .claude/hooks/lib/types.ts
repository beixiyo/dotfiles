// 权限管控共享类型

export type Decision = 'deny' | 'ask'
export type HookDecision = Decision | 'allow'
export type HitLevel = Decision

/** 单条命中：某段子命令触发了某条规则 */
export interface Hit {
  level: HitLevel
  reason: string
  /** 命中的子命令片段，用于在复合命令里定位 */
  segment: string
  /** 在原始命令中的起始下标，用于排序 */
  index: number
  /** 该 ask 命中在 Codex 下是否静默放行（当前仅 git 写） */
  codexAllow?: boolean
}

/** 单次调用的上下文 */
export interface Ctx {
  cmd: string
  filePath: string
  cwd: string
  isCodex: boolean
}

/** 决策结果；null 表示放行（静默 exit 0） */
export interface HookOutput {
  decision: Decision
  reason: string
}
