-- terminal preview 的骨架替换与过期输出回归；真实 shell job + terminal buffer
-- 只替换 Telescope 的构造边界，窗口、模块和进程均由逐 case child 回收
local H = dofile('tests/helpers.lua')
local T, child = H.new_set()

T['Loading 骨架替换与过期 job 守卫'] = function()
  child.lua_func(function()
    local define_preview
    package.loaded['telescope.previewers'] = {
      new_buffer_previewer = function(opts)
        define_preview = opts.define_preview
        return opts
      end,
    }
    require('plugins.specs.ui.telescope.git.shared')
      .term_previewer('Test', function(entry) return { 'sh', '-c', entry.cmd } end)

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
      local lines = vim.tbl_filter(function(line) return line ~= '' end,
        vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      return table.concat(lines, '\n')
    end

    -- 用真实文件握手取代 sleep 猜时序：在测试放行前，命令不能输出
    local old_ready, new_ready = vim.fn.tempname(), vim.fn.tempname()
    local old_buf = preview('while [ ! -f ' .. vim.fn.shellescape(old_ready)
      .. ' ]; do sleep 0.01; done; printf OLD')
    wait(function() return text(old_buf) == 'Loading…' end, 2000, '命令输出前必须显示 Loading…')
    local old_job = self.state.job_id
    local new_buf = preview('while [ ! -f ' .. vim.fn.shellescape(new_ready)
      .. ' ]; do sleep 0.01; done; printf "NEW\\nline2"')
    wait(function() return text(new_buf) == 'Loading…' end, 2000, '新任务等待期间必须显示骨架')
    vim.fn.writefile({}, old_ready)
    wait(function() return vim.fn.jobwait({ old_job }, 0)[1] ~= -1 end,
      2000, '被替换任务必须终结')
    check(not text(old_buf):find('OLD', 1, true), '被取代的旧任务不得写回旧 buffer')
    eq(text(new_buf), 'Loading…', '旧任务终结不能覆盖新 preview 的骨架')
    vim.fn.writefile({}, new_ready)
    wait(function() return text(new_buf) == 'NEW\nline2' end, 5000, '新输出必须完整替换骨架')

    local empty_buf = preview('true')
    wait(function() return text(empty_buf) == '' end, 2000, '空输出也必须清除骨架')
  end)
end

return T
