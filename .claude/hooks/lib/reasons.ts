/**
 * 命中原因文案的单一来源
 *
 * 正则引擎与 AST 引擎共用同一份文案——两处必须逐字一致（命中片段提示测试依赖它），
 * 集中在此杜绝两边漂移
 */
export const REASONS = {
  shutdown: '系统关机/重启命令',
  service: '系统服务控制命令',
  disk: '磁盘格式化/分区命令',
  pipeShell: 'pipe 到 shell',
  procSubst: '进程替换执行脚本',
  evalSubst: 'eval 执行命令替换',
  gitWrite: 'git 写操作',
  gitWriteC: 'git -C 跨仓库写操作',
  gitWriteOpt: 'git 带选项写操作',
  systemctl: 'systemctl 写操作',
  rm: '危险文件删除（根 / 家目录 / 系统目录 / .git）',
  envDump: '打印环境变量',
  exportDump: '打印导出变量',
  setDump: '打印全部 shell 变量',
} as const
