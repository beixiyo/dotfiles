-- 插件安装/更新后自动重新生成 .luarc.json（需要 bun）
local M = {}

local pending

function M.generate()
  if vim.fn.executable('bun') == 0 then
    vim.notify('[pack] bun 未安装，跳过 .luarc.json 生成。请安装后运行 :PackGenTypes', vim.log.levels.WARN)
    return
  end

  local script = vim.fn.stdpath('config') .. '/scripts/gen-luarc.ts'
  if vim.fn.filereadable(script) == 0 then return end

  vim.system({ 'bun', 'run', script }, {}, function(out)
    vim.schedule(function()
      if out.code == 0 then
        vim.notify('[pack] ' .. (out.stdout or ''):gsub('%s+$', ''), vim.log.levels.INFO)
      else
        vim.notify('[pack] .luarc.json 生成失败: ' .. (out.stderr or ''), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.schedule()
  if pending and not pending:is_closing() then
    pending:stop()
    pending:close()
  end
  -- 捕获本次定时器到 local，回调内只关闭/清理「自己这只」timer
  -- 避免延迟回调误关下一次 schedule 新建的 timer（丢失更新）
  local t = vim.uv.new_timer()
  pending = t
  t:start(3000, 0, vim.schedule_wrap(function()
    if not t:is_closing() then t:close() end
    if pending == t then pending = nil end
    M.generate()
  end))
end

local function needs_generate()
  local path = vim.fn.stdpath('config') .. '/.luarc.json'
  if vim.fn.filereadable(path) == 0 then return true end
  local content = vim.fn.readfile(path)
  local text = table.concat(content):gsub('%s', '')
  return text == '' or text == '{}'
end

function M.setup()
  if needs_generate() then M.generate() end

  vim.api.nvim_create_autocmd('PackChanged', {
    pattern = '*',
    callback = function(ev)
      local kind = ev.data and ev.data.kind
      if kind == 'install' or kind == 'update' then
        M.schedule()
      end
    end,
  })
end

return M
