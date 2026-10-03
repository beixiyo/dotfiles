-- shared.term_previewer 契约：jobstart 前先显示 Loading… 骨架，输出到达时清屏替换（空输出也清）；
-- 被新 entry 取代的旧 job 即使先结束也不得写回（job_id 守卫与 chanclose 任一生效即可）
-- 只替换 telescope.previewers 取出 define_preview，preview buffer / window 由测试按 Telescope 方式提供
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])

local define_preview
package.loaded['telescope.previewers'] = {
  new_buffer_previewer = function(opts)
    define_preview = opts.define_preview
    return opts
  end,
}
local S = require('plugins.specs.ui.telescope.git.shared')
S.term_previewer('Test', function(entry) return { 'sh', '-c', entry.cmd } end)

-- Telescope 每个 entry 新建 preview buffer，state 复用同一个 previewer
local self = { state = {} }
local win = vim.api.nvim_get_current_win()
local function preview(cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)
  self.state.bufnr, self.state.winid = buf, win
  define_preview(self, { cmd = cmd })
  return buf
end

local function text(buf)
  local lines = vim.tbl_filter(function(l) return l ~= '' end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  return table.concat(lines, '\n')
end

-- 旧 job 先结束（0.2s），新 job 后结束（0.5s）：旧输出若写回会出现 OLD
local old_buf = preview('sleep 0.2; printf OLD')
H.wait(function() return text(old_buf) == 'Loading…' end, 2000, '命令输出前 preview 应显示 Loading… 骨架')
local new_buf = preview('sleep 0.5; printf "NEW\\nline2"')
H.wait(function() return text(new_buf):find('NEW', 1, true) ~= nil end, 5000, '新 job 输出未写入 preview')
H.eq(text(new_buf), 'NEW\nline2', '输出到达后应清掉 Loading… 骨架，只保留命令输出')
H.check(text(old_buf):find('OLD', 1, true) == nil, '被取代的旧 job 不得写回 preview')

-- 空输出：骨架也必须被清掉，不能一直显示 Loading…
local empty_buf = preview('true')
H.wait(function() return text(empty_buf) == '' end, 2000, '空输出时 Loading… 骨架应被清除')

print('PASS: term_previewer skeleton and stale job guard')
