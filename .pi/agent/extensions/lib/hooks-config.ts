/**
 * settings.json 的 `customHooks` 配置读取
 *
 * 不用 `hooks`：这是本地扩展的自定义 key，避免与 pi 将来可能新增的官方 `hooks` 配置撞名
 *
 * 只读全局 ~/.pi/agent/settings.json：这里的值会被当 shell 命令执行，
 * 项目级 .pi/settings.json 来自仓库，不可信，故意不合并
 *
 * ```jsonc
 * {
 *   "customHooks": {
 *     "agentSettled": "bash ~/.zsh/notify/main.sh",   // string | string[]
 *     "uiPrompt": ["cmd1", "cmd2"]
 *   }
 * }
 * ```
 */
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

const SETTINGS_KEY = 'customHooks'

/** pi 的 hook 事件名 → 对应 Claude Code 事件，便于对照 */
export type HookName = 'agentSettled' | 'uiPrompt'

/** 读取某个 hook 的命令列表；未配置、类型不符、文件缺失/非法均返回空数组，绝不抛错 */
export function readHookCommands(name: HookName): string[] {
  try {
    const path = join(process.env.PI_CODING_AGENT_DIR ?? join(homedir(), '.pi', 'agent'), 'settings.json')
    const settings = JSON.parse(readFileSync(path, 'utf8')) as Record<string, unknown>
    const hooks = settings[SETTINGS_KEY] as Record<string, unknown> | undefined
    const value = hooks?.[name]
    const list = Array.isArray(value) ? value : [value]
    return list.filter((cmd): cmd is string => typeof cmd === 'string' && cmd.trim() !== '')
  }
  catch {
    return []
  }
}
