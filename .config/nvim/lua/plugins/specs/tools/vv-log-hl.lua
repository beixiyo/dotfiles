-- 日志文件语法高亮（本地 vendor）
---@type PackSpec
return {
  desc = '日志文件语法高亮',
  url  = 'beixiyo/vv-log-hl.nvim',
  event = {
    'BufReadPost *.log', 'BufReadPost *.out',
    'BufReadPost *.jsonl', 'BufReadPost *.ndjson',
    'BufReadPost *.log.*',
    'BufReadPost syslog', 'BufReadPost messages',
  },

  ---@type VVLogHlConfig
  opts = {
    extension = { 'log', 'out', 'jsonl', 'ndjson' },
    filename = { 'syslog', 'messages' },
    pattern = {
      '.*%.log%.%d+',   -- app.log.1
      '.*/log/.*',      -- files under log/
    },
    badge = false,
    keyword = {
      error = { 'PANIC' },
      pass = { 'COMPLETE', 'FINISHED' },
    },
  },
}
