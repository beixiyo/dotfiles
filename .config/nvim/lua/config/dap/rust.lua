-- Rust 与 LLDB 调试配置
local M = {}

---@param dap table
function M.setup(dap)
  -- 优先使用 PATH 中的 lldb-dap，macOS 下再尝试 Command Line Tools 自带版本
  local lldb_dap = vim.fn.exepath('lldb-dap')
  if lldb_dap == '' and vim.fn.executable('xcrun') == 1 then
    lldb_dap = vim.trim(vim.fn.system({ 'xcrun', '--find', 'lldb-dap' }))
    if vim.v.shell_error ~= 0 then lldb_dap = '' end
  end

  if lldb_dap == '' then
    vim.notify('lldb-dap is not installed', vim.log.levels.WARN)
    return
  end

  dap.adapters['lldb-dap'] = {
    type = 'executable',
    command = lldb_dap,
    name = 'lldb',
  }

  dap.configurations.rust = {
    {
      type = 'lldb-dap',
      request = 'launch',
      name = 'Build and launch current file',
      -- 单文件调试时先生成带调试信息的临时二进制，无需创建 Cargo 项目
      program = function()
        local source = vim.api.nvim_buf_get_name(0)
        local output_dir = vim.fn.stdpath('cache') .. '/dap-rust'
        local output = output_dir .. '/' .. vim.fn.fnamemodify(source, ':t:r')

        vim.fn.mkdir(output_dir, 'p')

        local result = vim.system({ 'rustc', '-g', source, '-o', output }, { text = true }):wait()
        if result.code ~= 0 then
          error(result.stderr or 'Failed to compile Rust file')
        end

        return output
      end,
      cwd = '${fileDirname}',
      stopOnEntry = false,
    },
    {
      type = 'lldb-dap',
      request = 'launch',
      name = 'Launch executable',
      -- Cargo 项目或已有构建产物可直接选择 target/debug 下的可执行文件
      program = function()
        return vim.fn.input('Executable: ', vim.uv.cwd() .. '/target/debug/', 'file')
      end,
      cwd = '${workspaceFolder}',
      stopOnEntry = false,
    },
  }
end

return M
