-- 构建命令生命周期：执行 spec.build、监听 PackChanged 更新、健康检查
-- 通过 .build_done 文件标记记录构建状态，避免重复构建
local spec = require('pack.spec')

local M = {}

local is_building = {}

function M.run(name, build_cmd, disabled_set)
  if disabled_set and disabled_set[name] then return end
  if not build_cmd or is_building[name] then return end

  local path = spec.get_root(name)
  if not path then return end

  local stamp = path .. '/.build_done'
  is_building[name] = true

  -- 判断是 Ex 命令 (`:TSUpdate`) 还是 shell 命令
  local is_vim_cmd, vim_cmd_str = false, ''
  if type(build_cmd) == 'string' and build_cmd:sub(1, 1) == ':' then
    is_vim_cmd, vim_cmd_str = true, build_cmd:sub(2)
  elseif type(build_cmd) == 'table' and type(build_cmd[1]) == 'string' and build_cmd[1]:sub(1, 1) == ':' then
    is_vim_cmd, vim_cmd_str = true, table.concat(build_cmd, ' '):sub(2)
  end

  if is_vim_cmd then
    vim.schedule(function()
      vim.notify('⚙️ Running ' .. name .. ' setup command...', vim.log.levels.INFO)
      pcall(vim.cmd.packadd, name)
      local ok, err = pcall(vim.cmd, vim_cmd_str)
      is_building[name] = false
      if ok then
        local f = io.open(stamp, 'w'); if f then f:close() end
        vim.notify('✅ ' .. name .. ' setup success.', vim.log.levels.INFO)
      else
        vim.notify('❌ ' .. name .. ' setup failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  else
    local final = {}
    if type(build_cmd) == 'string' then
      for w in build_cmd:gmatch('%S+') do table.insert(final, w) end
    else
      final = build_cmd
    end
    vim.schedule(function() vim.notify('⚙️ Building ' .. name .. ' (Background)...', vim.log.levels.INFO) end)
    vim.system(final, { cwd = path }, function(out)
      is_building[name] = false
      if out.code == 0 then
        local f = io.open(stamp, 'w'); if f then f:close() end
        vim.schedule(function() vim.notify('✅ ' .. name .. ' build success.', vim.log.levels.INFO) end)
      else
        vim.schedule(function()
          vim.notify('❌ ' .. name .. ' build failed: ' .. (out.stderr or 'Unknown Error'), vim.log.levels.ERROR)
        end)
      end
    end)
  end
end

function M.is_building(name) return is_building[name] == true end

-- 监听 PackChanged：更新/安装后清除构建标记
-- 由 pack/init.lua 在 vim.pack.add 之前为所有带 build 的 spec 注册一次，不能等到插件加载时才注册：
-- 懒加载插件在加载前被更新时没人监听，.build_done 留着，之后 check_health 会误以为已构建
-- 已加载的插件立即重建；未加载的只清标记，留给加载时的 check_health 补跑（避免为了构建提前 packadd）
local listening = {}
local group = vim.api.nvim_create_augroup('PackBuild', { clear = true })

---@param name string
---@param build_cmd string|string[]
---@param disabled_set table<string, boolean>?
---@param is_loaded fun(name: string): boolean
function M.setup_listener(name, build_cmd, disabled_set, is_loaded)
  if disabled_set and disabled_set[name] then return end
  if not build_cmd or listening[name] then return end
  listening[name] = true
  vim.api.nvim_create_autocmd('PackChanged', {
    group = group,
    pattern = '*',
    callback = function(ev)
      if ev.data.spec.name == name and (ev.data.kind == 'update' or ev.data.kind == 'install') then
        os.remove(ev.data.path .. '/.build_done')
        if is_loaded(name) then M.run(name, build_cmd, disabled_set) end
      end
    end,
  })
end

-- 健康检查：若插件未构建则触发构建
function M.check_health(name, build_cmd, disabled_set)
  if disabled_set and disabled_set[name] then return end
  if not build_cmd then return end
  local path = spec.get_root(name)
  if path and vim.fn.filereadable(path .. '/.build_done') == 0 then
    M.run(name, build_cmd, disabled_set)
  end
end

return M
