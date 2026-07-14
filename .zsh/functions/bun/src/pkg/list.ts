import { parseArgs } from 'node:util'
import { resolveAdapter } from './adapters'
import { COLORS } from '../shared'

const C = COLORS

const { values } = parseArgs({
  args: process.argv.slice(2),
  options: {
    pm: { type: 'string' },
  },
})

if (!values.pm) {
  console.error('用法: bun run list.ts --pm=<pacman|apt|brew>')
  process.exit(1)
}

const adapter = resolveAdapter(values.pm)
const pkgs = await adapter.list()

// 默认按磁盘占用降序
pkgs.sort((a, b) => b.sizeBytes - a.sizeBytes)

// 计算列宽以对齐
const maxName = Math.min(Math.max(...pkgs.map(p => p.name.length), 4), 35)
const maxVer = Math.min(Math.max(...pkgs.map(p => p.version.length), 3), 20)
const sizeWidth = 10

for (const pkg of pkgs) {
  const name = pkg.name.padEnd(maxName)
  const ver = pkg.version.padEnd(maxVer)
  const size = (pkg.size || '-').padStart(sizeWidth)
  const desc = pkg.description.slice(0, 60)

  // 字段 1: 纯名称（供 fzf {1} 提取）  字段 2+: 带色显示行
  const display = `${C.Cyan}${name}${C.Reset}  ${ver}  ${C.Yellow}${size}${C.Reset}  ${C.Black}${desc}${C.Reset}`
  process.stdout.write(`${pkg.name}\t${display}\n`)
}

process.exit(0)
