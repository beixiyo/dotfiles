-- 探针：启动 / 退出耗时归因。方法与坑见 perf-startup-exit.md
-- 验证环境：nvim 0.13.0-dev-1617（2026-10-22），三种模式均用完整配置 headless 端到端跑过
--
-- 用法（PERF_OUT 为输出文件，必填）：
--   exit：给 QuitPre / ExitPre / VimLeavePre / VimLeave 的每个 handler 计时，启动完成后再挂
--     PERF_MODE=exit PERF_OUT=/tmp/x.log nvim --headless FILE +'lua vim.wait(3000)' +'luafile probe-startup-exit.lua' +qa!
--   query：统计 treesitter query 编译耗时（get = 含 runtime 查找与 memoize，parse = 纯编译）
--     PERF_MODE=query PERF_OUT=/tmp/x.log nvim --headless --cmd 'luafile probe-startup-exit.lua' FILE +qa!
--   lsp：逐个停止 LSP client 并测量到 rpc 关闭的耗时（即 :qa 时 vim.lsp exit handler 等待的条件）
--     PERF_MODE=lsp PERF_OUT=/tmp/x.log nvim --headless FILE +'lua vim.wait(4000, function() local c = vim.lsp.get_clients()[1]; return c and c.initialized end)' +'luafile probe-startup-exit.lua' +qa!
--
-- headless 下 `+qa!` 在 VimEnter 之前执行，VimEnter 不会触发；结果统一在 VimLeave(Pre) 落盘

local MODE = vim.env.PERF_MODE
local OUT = assert(vim.env.PERF_OUT, 'PERF_OUT 未设置')

local function flush(lines)
  local f = assert(io.open(OUT, 'w'))
  f:write(('-- mode=%s nvim=%s\n'):format(MODE, tostring(vim.version())))
  f:write(table.concat(lines, '\n') .. '\n')
  f:close()
end

local function ms_since(t) return (vim.uv.hrtime() - t) / 1e6 end


--- 删除再按原顺序重建每个 handler，外面包一层计时
--- 只保证这批 handler 之间的相对顺序；之后再注册的 handler 仍排在它们后面，与原状一致
local function probe_exit()
  local rows = {}

  for _, ev in ipairs({ 'QuitPre', 'ExitPre', 'VimLeavePre', 'VimLeave' }) do
    for _, a in ipairs(vim.api.nvim_get_autocmds({ event = ev })) do
      local label = ('%s %s | %s'):format(ev, a.group_name or '-',
        a.desc or (a.command ~= '' and a.command) or tostring(a.callback))
      local cb, cmd = a.callback, a.command

      pcall(vim.api.nvim_del_autocmd, a.id)
      vim.api.nvim_create_autocmd(ev, {
        group = a.group,
        pattern = a.pattern ~= '*' and a.pattern or nil,
        callback = function(args)
          local t = vim.uv.hrtime()
          local ok, err = pcall(function()
            if type(cb) == 'function' then cb(args)
            elseif type(cb) == 'string' then vim.fn[cb](args)
            else vim.cmd(cmd) end
          end)
          rows[#rows + 1] = { ms_since(t), label .. (ok and '' or (' ERROR ' .. tostring(err))) }
        end,
      })
    end
  end

  vim.api.nvim_create_autocmd('VimLeave', {
    callback = function()
      table.sort(rows, function(x, y) return x[1] > y[1] end)
      local lines, total = {}, 0
      for _, r in ipairs(rows) do
        total = total + r[1]
        lines[#lines + 1] = ('%8.2fms %s'):format(r[1], r[2])
      end
      table.insert(lines, 1, ('total %.2fms'):format(total))
      flush(lines)
    end,
  })
end


--- query.get 会触发 parse；两者都记，能区分「查找 / 拼接文件」和「编译」
local function probe_query()
  local rows = {}
  local q = vim.treesitter.query

  local get = q.get
  q.get = function(lang, name)
    local t = vim.uv.hrtime()
    local r = get(lang, name)
    rows[#rows + 1] = ('get   %-12s %-20s %7.1fms'):format(lang, name, ms_since(t))
    return r
  end

  local parse = q.parse
  q.parse = function(lang, src)
    local t = vim.uv.hrtime()
    local r = parse(lang, src)
    rows[#rows + 1] = ('parse %-12s %-20s %7.1fms (%d bytes)'):format(lang, '', ms_since(t), #src)
    return r
  end

  vim.api.nvim_create_autocmd('VimLeavePre', { callback = function() flush(rows) end })
end


--- client:is_stopped() 在 stop() 后立即为 true，不能用来测退出耗时；core exit handler 等的是 rpc.is_closing()
local function probe_lsp()
  local rows = {}

  for _, c in ipairs(vim.lsp.get_clients({ _uninitialized = true })) do
    local t = vim.uv.hrtime()
    c:stop()
    local ok = vim.wait(2000, function() return c.rpc.is_closing() end, 1)
    rows[#rows + 1] = ('%-20s init=%-5s closed=%-5s %7.1fms exit_timeout=%s'):format(
      c.name, tostring(c.initialized), tostring(ok), ms_since(t), tostring(c.exit_timeout))
  end

  flush(rows)
end


local probes = { exit = probe_exit, query = probe_query, lsp = probe_lsp }
assert(probes[MODE], 'PERF_MODE 应为 exit / query / lsp，当前：' .. tostring(MODE))()
