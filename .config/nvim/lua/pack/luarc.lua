-- LuaLS 项目类型库查询与清单生成；新增本地 vendor 不依赖旧清单也能取得基础类型
local M = {}

local pending
local config_path = vim.fn.stdpath('config')
local manifest_path = config_path .. '/.luarc-libraries.json'
local vendor_root = vim.fs.normalize(config_path .. '/vendors')

local function is_vendor_project(root)
  return root and vim.fs.dirname(root) == vendor_root
    and vim.fn.isdirectory(root .. '/lua') == 1
end

local function load_manifest()
  local file = io.open(manifest_path, 'r')
  if not file then return nil end

  local content = file:read('*a')
  file:close()

  local ok, manifest = pcall(vim.json.decode, content)
  return ok and type(manifest) == 'table' and manifest or nil
end

--- 返回项目类型库；清单尚未包含本地 vendor 时兜底提供 Neovim/luv 基础类型
---@param root string?
---@return string[]
function M.libraries_for(root)
  if not root then return {} end
  root = vim.fs.normalize(root)

  local manifest = load_manifest()
  local project = manifest and manifest.projects and manifest.projects[root]
  if not project and not is_vendor_project(root) then return {} end

  local libraries = vim.deepcopy(manifest and manifest.base or {
    '${3rd}/luv/library',
    vim.env.VIMRUNTIME .. '/lua',
  })
  vim.list_extend(libraries, project or {})
  return libraries
end

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
  for _, path in ipairs({
    vim.fn.stdpath('config') .. '/.luarc.json',
    manifest_path,
  }) do
    if vim.fn.filereadable(path) == 0 then return true end
    local content = vim.fn.readfile(path)
    local text = table.concat(content):gsub('%s', '')
    if text == '' or text == '{}' then return true end
  end

  -- 本地 clone 的插件不会产生 PackChanged；不能只以清单文件存在判断有效
  local manifest = load_manifest()
  if not (manifest and manifest.projects) then return true end
  for _, lua_dir in ipairs(vim.fn.glob(vendor_root .. '/*/lua', false, true)) do
    local project = vim.fs.normalize(vim.fs.dirname(lua_dir))
    if is_vendor_project(project) and not manifest.projects[project] then return true end
  end
  return false
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
