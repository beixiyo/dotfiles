import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'

const configRoot = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config')
const nvimConfig = path.join(configRoot, 'nvim', 'init.lua')

/**
 * 使用用户的 Neovim 配置执行与 <leader>c. 相同的行尾清理
 */
export function runNvimCleanTrailing(filePath: string, cwd: string): boolean {
  const nvim = findExecutable(path.dirname(filePath), 'nvim')
  if (!nvim || !fs.existsSync(nvimConfig)) return false

  runProcess(nvim, [
    '--headless',
    '-u',
    nvimConfig,
    filePath,
    '-c',
    'VVCleanTrailing',
    '-c',
    'update',
    '-c',
    'qa!',
  ], { cwd })
  return true
}
