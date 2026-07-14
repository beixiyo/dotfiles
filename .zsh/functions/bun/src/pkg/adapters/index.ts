import { createPacmanAdapter } from './pacman'
import { createAptAdapter } from './apt'
import { createBrewAdapter } from './brew'
import type { PkgAdapter } from './types'

const adapters: Record<string, () => PkgAdapter> = {
  pacman: createPacmanAdapter,
  apt: createAptAdapter,
  brew: createBrewAdapter,
}

export function resolveAdapter(pm: string): PkgAdapter {
  const factory = adapters[pm]
  if (!factory) {
    const supported = Object.keys(adapters).join(', ')
    throw new Error(`不支持的包管理器: ${pm}（支持: ${supported}）`)
  }
  return factory()
}

export type { PkgAdapter, PkgInfo } from './types'
export { formatSize, parseSizeToBytes } from './types'
