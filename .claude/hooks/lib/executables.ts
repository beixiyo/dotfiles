import fs from 'node:fs'
import path from 'node:path'

const EXECUTABLE_SUFFIXES = process.platform === 'win32'
  ? ['', '.cmd', '.exe', '.bat']
  : ['']

/**
 * 就近查找项目本地可执行文件，找不到时再从当前 PATH 查找全局可执行文件
 */
export function findExecutable(startDir: string, name: string): string | null {
  let dir = path.resolve(startDir)

  while (true) {
    for (const suffix of EXECUTABLE_SUFFIXES) {
      const executable = path.join(dir, 'node_modules', '.bin', `${name}${suffix}`)
      if (isExecutable(executable)) return executable
    }

    const parent = path.dirname(dir)
    if (parent === dir) break
    dir = parent
  }

  for (const directory of (process.env.PATH ?? '').split(path.delimiter)) {
    if (!directory) continue

    for (const suffix of EXECUTABLE_SUFFIXES) {
      const executable = path.join(directory, `${name}${suffix}`)
      if (isExecutable(executable)) return executable
    }
  }

  return null
}

function isExecutable(filePath: string): boolean {
  try {
    fs.accessSync(filePath, fs.constants.X_OK)
    return true
  }
  catch {
    return false
  }
}
