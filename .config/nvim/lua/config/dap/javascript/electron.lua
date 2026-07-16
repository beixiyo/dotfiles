-- electron-vite 主进程与渲染进程调试配置
local M = {}

local debug_port = 9222
local attach_listener = 'electron_renderer_attach'

-- 只沿当前文件与工作目录向上识别项目，不假设 monorepo 的目录结构
local function find_project_root()
  local starts = {
    vim.fn.expand('%:p:h'),
    vim.fn.getcwd(),
  }

  for _, start in ipairs(starts) do
    local dir = start ~= '' and vim.fs.normalize(start) or nil

    while dir do
      local package_json = dir .. '/package.json'
      if vim.fn.filereadable(package_json) == 1 then
        local ok, package = pcall(vim.json.decode, table.concat(vim.fn.readfile(package_json), '\n'))
        if ok and type(package) == 'table' then
          local dependencies = vim.tbl_extend(
            'force',
            package.dependencies or {},
            package.devDependencies or {}
          )

          if dependencies['electron-vite'] then return dir end
        end
      end

      local parent = vim.fs.dirname(dir)
      dir = parent ~= dir and parent or nil
    end
  end
end

-- 延迟到启动调试时解析，确保切换项目后使用当前 buffer 的项目根目录
local function project_path(relative)
  return function()
    local root = find_project_root()
    if not root then
      vim.notify('No Electron project using electron-vite found', vim.log.levels.ERROR)
      return require('dap').ABORT
    end

    return relative and (root .. '/' .. relative) or root
  end
end

-- Vite sourcemap 中的相对 source 以 Vite root 为基准，通常可由最近的 index.html 确定
local function find_renderer_root(project_root)
  local current_file = vim.fn.expand('%:p')
  local dir = current_file ~= '' and vim.fs.dirname(current_file) or nil

  while dir and vim.startswith(dir, project_root) do
    if vim.fn.filereadable(dir .. '/index.html') == 1 then return dir end

    local parent = vim.fs.dirname(dir)
    dir = parent ~= dir and parent or nil
  end

  return project_root
end

local function renderer_path()
  return function()
    local root = find_project_root()
    if not root then
      vim.notify('No Electron project using electron-vite found', vim.log.levels.ERROR)
      return require('dap').ABORT
    end

    return find_renderer_root(root)
  end
end

local function executable_path()
  return vim.fn.has('win32') == 1
      and 'node_modules/.bin/electron-vite.cmd'
    or 'node_modules/.bin/electron-vite'
end

local function main_configuration(skip_files, root)
  local path = function(relative)
    return root and (root .. (relative and ('/' .. relative) or '')) or project_path(relative)
  end

  return {
    type = 'pwa-node',
    request = 'launch',
    name = 'Launch Electron main process',
    cwd = path(),
    runtimeExecutable = path(executable_path()),
    runtimeArgs = {
      '--sourcemap',
      '--remoteDebuggingPort',
      tostring(debug_port),
    },
    sourceMaps = true,
    autoAttachChildProcesses = true,
    skipFiles = skip_files,
    console = 'integratedTerminal',
  }
end

local function renderer_configuration(skip_files, root, web_root)
  return {
    type = 'pwa-chrome',
    request = 'attach',
    name = 'Attach Electron renderer process',
    port = debug_port,
    webRoot = web_root or renderer_path(),
    sourceMaps = true,
    skipFiles = skip_files,
    timeout = 60000,
  }
end

-- Electron 创建 Renderer 后才会开放 DevTools 端口，因此 attach 前需要等待端口就绪
local function session_tree_stopped(session)
  if session.stopped_thread_id then return true end

  for _, child in pairs(session.children or {}) do
    if session_tree_stopped(child) then return true end
  end

  return false
end

local function wait_for_renderer(main_session, callback)
  local started = vim.uv.now()

  local function try_connect()
    -- Main session 已结束时停止等待，避免退出调试后仍轮询并误报超时
    if main_session.closed then return end

    -- Main 停在早期断点时 Renderer 页面可能尚未创建，继续运行后再开始 attach
    if session_tree_stopped(main_session) then
      started = vim.uv.now()
      vim.defer_fn(try_connect, 200)
      return
    end

    local socket = vim.uv.new_tcp()
    socket:connect('127.0.0.1', debug_port, function(err)
      socket:close()

      vim.schedule(function()
        if main_session.closed then
          return
        elseif not err then
          callback()
        elseif vim.uv.now() - started >= 60000 then
          vim.notify('Timed out waiting for Electron renderer debug port', vim.log.levels.ERROR)
        else
          vim.defer_fn(try_connect, 200)
        end
      end)
    end)
  end

  -- electron-vite 会先开放端口再执行 Main 入口，留出窗口让启动期断点先命中
  vim.defer_fn(try_connect, 5000)
end

local function combined_configuration(skip_files)
  local config = {
    type = 'pwa-node',
    request = 'launch',
    name = 'Launch Electron and attach renderer',
  }

  return setmetatable(config, {
    __call = function()
      local dap = require('dap')
      local root = find_project_root()
      if not root then
        vim.notify('No Electron project using electron-vite found', vim.log.levels.ERROR)
        return vim.tbl_extend('force', config, { runtimeExecutable = dap.ABORT })
      end

      local renderer_root = find_renderer_root(root)

      dap.listeners.after.event_initialized[attach_listener] = function(session)
        if session.config.name ~= config.name then return end

        dap.listeners.after.event_initialized[attach_listener] = nil
        wait_for_renderer(session, function()
          dap.run(renderer_configuration(skip_files, root, renderer_root), { new = true })
        end)
      end

      return vim.tbl_extend('force', main_configuration(skip_files, root), { name = config.name })
    end,
  })
end

---@param skip_files string[]
---@return table[]
function M.node_configurations(skip_files)
  return {
    main_configuration(skip_files),
  }
end

---@param skip_files string[]
---@return table[]
function M.browser_configurations(skip_files)
  return {
    combined_configuration(skip_files),
    renderer_configuration(skip_files),
  }
end

return M
