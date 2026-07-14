-- Go 与 Delve 调试配置
local M = {}

local developer_mode_command = 'sudo /usr/sbin/DevToolsSecurity -enable'

-- macOS 上 Delve 依赖 Developer Tools 权限，启动前检查可避免模糊的 Failed to launch
function M.debug_error()
  if vim.fn.has('mac') == 0 then return nil end

  local result = vim.system({ '/usr/sbin/DevToolsSecurity', '-status' }, { text = true }):wait()
  local output = (result.stdout or '') .. (result.stderr or '')

  if output:find('disabled', 1, true) then
    return 'Go debugging requires macOS Developer Mode. Run `' .. developer_mode_command .. '`, then retry'
  end

  return nil
end

---@param dap table
function M.setup(dap)
  if vim.fn.executable('dlv') ~= 1 then
    vim.notify('Delve is not installed', vim.log.levels.WARN)
    return
  end

  require('dap-go').setup()

  -- Delve 使用 dlvCwd 执行 go build，cwd 则是被调试程序的运行目录
  -- 两者跟随当前文件，避免从 monorepo 或父目录启动 Neovim 时找不到 go.mod
  local function go_dir()
    return vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  end

  local function go_program()
    local err = M.debug_error()
    if err then error(err, 0) end

    return go_dir()
  end

  dap.configurations.go = {
    {
      type = 'go',
      request = 'launch',
      name = 'Debug current package',
      program = go_program,
      dlvCwd = go_dir,
      cwd = go_dir,
      outputMode = 'remote',
    },
  }
end

return M
