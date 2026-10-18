-- nvim-treesitter (main) 编译 parser 的外部依赖检测，只返回面向用户的英文提示，不替用户安装
-- 依据 nvim-treesitter README / health.lua：tree-sitter CLI >= 0.26.1（不能用 npm 装）、C 编译器、curl、tar
local M = {}

local MIN_CLI = { 0, 26, 1 }

local CLI_HELP = table.concat({
  'tree-sitter CLI (>= 0.26.1) is required to build parsers. Install it with one of:',
  '  macOS:  brew install tree-sitter-cli',
  '  Arch:   sudo pacman -S tree-sitter-cli',
  '  Any:    cargo install --locked tree-sitter-cli   (not npm)',
  '  Binary: https://github.com/tree-sitter/tree-sitter/releases',
  '  Docs:   https://github.com/nvim-treesitter/nvim-treesitter#requirements',
}, '\n')

local function has_compiler()
  if vim.env.CC and vim.fn.executable(vim.env.CC) == 1 then return true end

  -- macOS 的 /usr/bin/cc 是桩程序，没装 Command Line Tools 时恒存在，必须看 xcode-select
  if vim.uv.os_uname().sysname == 'Darwin' then
    return vim.system({ 'xcode-select', '-p' }):wait().code == 0
  end

  for _, exe in ipairs({ 'cc', 'gcc', 'clang' }) do
    if vim.fn.executable(exe) == 1 then return true end
  end
  return false
end

local function cli_ok()
  if vim.fn.executable('tree-sitter') == 0 then return false end

  local out = vim.system({ 'tree-sitter', '--version' }, { text = true }):wait()
  local raw = (out.stdout or ''):match('%d+%.%d+%.%d+')
  local version = raw and vim.version.parse(raw)
  return not (version and vim.version.lt(version, MIN_CLI))
end

--- 依赖齐全返回 nil，否则返回可直接展示给用户的英文提示
---@return string?
function M.missing_message()
  local lines = {}

  if not cli_ok() then table.insert(lines, CLI_HELP) end

  for _, exe in ipairs({ 'curl', 'tar' }) do
    if vim.fn.executable(exe) == 0 then
      table.insert(lines, exe .. ' is required to download parsers, install it with your package manager.')
    end
  end

  if not has_compiler() then
    local hint = vim.uv.os_uname().sysname == 'Darwin' and 'run `xcode-select --install`' or 'install gcc or clang'
    table.insert(lines, 'A C compiler is required to build parsers: ' .. hint .. '.')
  end

  if #lines == 0 then return nil end
  return table.concat(lines, '\n') .. '\nThen reopen the file. Details: :checkhealth nvim-treesitter'
end

return M
