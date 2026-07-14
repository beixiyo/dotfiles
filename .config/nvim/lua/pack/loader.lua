-- 插件加载器：消费 spec 的 dir / dependencies / main / opts / config，幂等加载
-- config 签名：
--   普通:   config(plugin, opts)          — 对齐 lazy.nvim
--   manual: config(plugin, { load = fn }) — 逃生舱：spec 自己决定加载时机
-- 默认 config（没显式写）：require(main).setup(opts)；main = false 时跳过
local spec_mod = require('pack.spec')
local build = require('pack.build')

local M = {}

-- 全局状态：哪些插件已经加载完成
local initialized = {}

-- 检测插件目录是否为不完整克隆
-- 1) 目录内无可见文件（只有 .git）；2) main 可 require 但 lua/ 目录缺失
local function is_corrupt_clone(path, needs_lua)
  if not path then return false end
  local items = vim.fn.readdir(path)
  local visible = vim.tbl_filter(function(f) return f:sub(1, 1) ~= '.' end, items)
  if #visible == 0 then return true end
  if needs_lua and vim.fn.isdirectory(path .. '/lua') == 0 then return true end
  return false
end

-- 解析 opts：table 或 function(plugin) -> table
local function resolve_opts(plugin)
  local o = plugin.opts
  if type(o) == 'function' then return o(plugin) end
  return o
end

-- 主加载函数。幂等：第二次调用对同一 spec 早退
-- disabled_set: 被用户禁用的插件名集合（来自 sync 阶段）
function M.load(spec, disabled_set)
  local name = spec_mod.resolve_name(spec)
  if not name then
    vim.notify('[pack] spec 缺少 id/url/dir/name，无法加载: ' .. vim.inspect(spec), vim.log.levels.ERROR)
    return
  end
  if disabled_set and disabled_set[name] then return end
  if initialized[name] then return end

  -- 本地 vendor：挂载到 rtp 最前
  if spec.dir then
    vim.opt.rtp:prepend(spec.dir)
  end

  -- 构建健康检查 & 更新监听
  build.check_health(name, spec.build, disabled_set)
  if spec.build then
    build.setup_listener(name, spec.build, disabled_set)
  end

  -- spec.init：packadd 前执行，可用来设 vim.g.xxx 等预配置
  if type(spec.init) == 'function' then
    local ok, err = pcall(spec.init, spec)
    if not ok then
      vim.notify('[pack] ' .. name .. ' init failed: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end

  -- 加载依赖：dependencies 是 url 数组，在 vim.pack.add 阶段已下载，这里只负责 packadd
  if spec.dependencies then
    for _, dep_url in ipairs(spec.dependencies) do
      local dep_name = spec_mod.get_name(dep_url)
      if dep_name then
        local ok, err = pcall(vim.cmd.packadd, dep_name)
        if not ok and not tostring(err):match('E919') then
          vim.notify('[pack] ' .. name .. ' dep [' .. dep_name .. '] missing', vim.log.levels.WARN)
        end
      end
    end
  end

  -- 加载主插件
  local packadd_ok, packadd_err = pcall(vim.cmd.packadd, name)
  if not packadd_ok and not tostring(packadd_err):match('E919') then
    vim.notify('[pack] Failed to packadd ' .. name .. ': ' .. tostring(packadd_err), vim.log.levels.WARN)
  end

  if build.is_building(name) then
    vim.notify('⏳ ' .. name .. ' is building in background. Some features might not be ready.', vim.log.levels.WARN)
  end

  -- lazy='manual' 模式：config 已在 pack/init.lua 启动期执行过（ctx={load=fn}）
  -- loader.load 被 ctx.load() 触发时只做 packadd/dependencies，不再重跑 config
  if spec.lazy == 'manual' then
    initialized[name] = true
    return
  end

  -- 解析 main：显式 > 自动推断；main = false 明确跳过 require
  local main = spec_mod.resolve_main(spec)

  -- 预 require 一次 main：让 corrupt clone 能被检测；后续 config 里由用户自己 require 拿对象
  if main then
    local req_ok, req_err = pcall(require, main)
    if not req_ok then
      local root = spec_mod.get_root(name)
      if root and is_corrupt_clone(root, true) then
        vim.fn.delete(root, 'rf')
        vim.notify('[pack] ' .. name .. ' 克隆不完整，已自动删除，请重启 Neovim', vim.log.levels.WARN)
        return
      elseif root then
        vim.notify('[pack] ' .. name .. ' main[' .. main .. '] require 失败: ' .. tostring(req_err), vim.log.levels.ERROR)
        return
      end
    end
  end

  local opts = resolve_opts(spec)

  -- config 优先级：显式 config(plugin, opts) > 默认 require(main).setup(opts)
  if type(spec.config) == 'function' then
    local ok, err = pcall(spec.config, spec, opts)
    if not ok then
      vim.notify('[pack] ' .. name .. ' config failed: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
  elseif main then
    local ok, err = pcall(function()
      local obj = require(main)
      if type(obj) == 'table' and type(obj.setup) == 'function' then
        if opts == nil then obj.setup() else obj.setup(opts) end
      end
    end)
    if not ok then
      vim.notify('[pack] ' .. name .. ' setup failed: ' .. tostring(err), vim.log.levels.ERROR)
      return
    end
  end

  initialized[name] = true
end

function M.is_loaded(name) return initialized[name] == true end

return M
