-- 动态选择并调试当前项目的 package.json script
local M = {}

local listener = 'package_script_browser_attach'

local lock_managers = {
  { files = { 'pnpm-lock.yaml' }, manager = 'pnpm' },
  { files = { 'bun.lock', 'bun.lockb' }, manager = 'bun' },
  { files = { 'yarn.lock' }, manager = 'yarn' },
  { files = { 'package-lock.json', 'npm-shrinkwrap.json' }, manager = 'npm' },
}

local function read_package(path)
  local ok, package = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
  return ok and type(package) == 'table' and package or nil
end

-- 以当前文件为首选起点，避免 monorepo 中误用工作区根目录的 scripts
local function find_package()
  local starts = {
    vim.fn.expand('%:p:h'),
    vim.fn.getcwd(),
  }

  for _, start in ipairs(starts) do
    if start ~= '' then
      local path = vim.fs.find('package.json', { path = start, upward = true })[1]
      local package = path and read_package(path) or nil
      if package and type(package.scripts) == 'table' then
        return package, vim.fs.dirname(path)
      end
    end
  end
end

local function package_manager(package, package_dir)
  local declared = type(package.packageManager) == 'string'
      and package.packageManager:match('^([^@]+)')
    or nil
  if declared then return declared end

  local dir = package_dir
  while dir do
    for _, candidate in ipairs(lock_managers) do
      for _, filename in ipairs(candidate.files) do
        if vim.uv.fs_stat(dir .. '/' .. filename) then return candidate.manager end
      end
    end

    local parent = vim.fs.dirname(dir)
    dir = parent ~= dir and parent or nil
  end

  return 'npm'
end

local function select_script(scripts)
  local items = {}
  for name, command in pairs(scripts) do
    -- 分隔标题不是可执行命令，不放进选择列表
    if type(command) == 'string' and not command:match('^%-+$') then
      table.insert(items, { name = name, command = command })
    end
  end

  table.sort(items, function(a, b) return a.name < b.name end)
  if #items == 0 then return nil end

  local co = coroutine.running()
  vim.ui.select(items, {
    prompt = 'Package script',
    kind = 'package-script',
    format_item = function(item) return item.name .. '  ' .. item.command end,
  }, function(item)
    vim.schedule(function() coroutine.resume(co, item) end)
  end)

  return coroutine.yield()
end

-- Dev server 的输出可能包含 ANSI 颜色序列，解析 URL 前先移除
local function strip_ansi(text)
  return text:gsub('\27%[[0-?]*[ -/]*[@-~]', '')
end

local function browser_url(output)
  local url = strip_ansi(output):match('https?://[%w%._%-]+:%d+')
  if not url then return nil end

  -- 0.0.0.0 是监听地址，浏览器访问时应使用本机地址
  return url:gsub('://0%.0%.0%.0', '://localhost')
end

local function root_session(session)
  while session.parent do
    session = session.parent
  end

  return session
end

local function attach_browser_when_ready(package_dir, skip_files)
  local dap = require('dap')
  local attached = false

  dap.listeners.after.event_output[listener] = function(session, body)
    local root = root_session(session)
    if not root.config.package_script_browser then return end

    local url = not attached and browser_url(body.output or '') or nil
    if not url then return end

    attached = true
    dap.listeners.after.event_output[listener] = nil

    vim.schedule(function()
      dap.run({
        type = 'pwa-chrome',
        request = 'launch',
        name = 'Attach package script browser',
        url = url,
        webRoot = package_dir,
        sourceMaps = true,
        skipFiles = skip_files,
      }, { new = true })
    end)
  end
end

---@param skip_files string[]
---@return table[]
function M.configurations(skip_files)
  local config = {
    type = 'pwa-node',
    request = 'launch',
    name = 'Debug package.json script',
  }

  return {
    setmetatable(config, {
      __call = function()
        local dap = require('dap')
        local package, package_dir = find_package()
        if not package then
          vim.notify('No package.json with scripts found', vim.log.levels.ERROR)
          return vim.tbl_extend('force', config, { runtimeExecutable = dap.ABORT })
        end

        local script = select_script(package.scripts)
        if not script then
          return vim.tbl_extend('force', config, { runtimeExecutable = dap.ABORT })
        end

        local manager = package_manager(package, package_dir)
        if vim.fn.executable(manager) ~= 1 then
          vim.notify('Package manager is not executable: ' .. manager, vim.log.levels.ERROR)
          return vim.tbl_extend('force', config, { runtimeExecutable = dap.ABORT })
        end

        local runtime_args = manager == 'yarn'
            and { script.name }
          or { 'run', script.name }

        attach_browser_when_ready(package_dir, skip_files)

        return vim.tbl_extend('force', config, {
          cwd = package_dir,
          runtimeExecutable = manager,
          runtimeArgs = runtime_args,
          package_script_browser = true,
          sourceMaps = true,
          autoAttachChildProcesses = true,
          skipFiles = skip_files,
          console = 'integratedTerminal',
          env = {
            FORCE_COLOR = '0',
            NO_COLOR = '1',
          },
        })
      end,
    }),
  }
end

return M
