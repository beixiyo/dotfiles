-- LuaLS workspace root 与项目类型库配置

local M = {}

local root_markers = {
  '.emmyrc.json',
  '.luarc.json',
  '.luarc.jsonc',
  '.luacheckrc',
  '.stylua.toml',
  'stylua.toml',
  'selene.toml',
  'selene.yml',
  '.git',
}

local function nearest_root(path)
  local dir = vim.fs.dirname(path)
  while dir do
    for _, marker in ipairs(root_markers) do
      if vim.uv.fs_stat(vim.fs.joinpath(dir, marker)) then return dir end
    end

    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then return nil end
    dir = parent
  end
end

local function root_dir(bufnr, on_dir)
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local home = vim.fs.normalize(vim.uv.os_homedir() or '')
  local marker_root = nearest_root(path)

  if marker_root and vim.fs.normalize(marker_root) ~= home then
    on_dir(marker_root)
    return
  end

  -- HOME 本身是 dotfiles Git 仓库，不能让零散 Lua 配置把整个 HOME 变成 workspace
  -- ~/.config/<app> 与 ~/.<app> 各自作为独立项目；HOME 顶层 Lua 文件不启动 lua_ls
  local relative = home ~= '' and path:sub(#home + 2) or ''
  local parts = vim.split(relative, '/', { plain = true, trimempty = true })
  local root

  if parts[1] == '.config' and parts[2] then
    root = vim.fs.joinpath(home, parts[1], parts[2])
  elseif parts[1] and parts[2] and parts[1]:sub(1, 1) == '.' then
    root = vim.fs.joinpath(home, parts[1])
  end

  if root and vim.uv.fs_stat(root) then on_dir(root) end
end

local function inject_project_libraries(_, config)
  local libraries = require('pack.luarc').libraries_for(config.root_dir)
  if #libraries == 0 then return end

  -- Client.create() 会在 before_init 之前保存 settings 引用，因此必须原地修改，
  -- 不能用 tbl_deep_extend() 替换整个 table，否则 server 收不到新增配置
  local lua_settings = config.settings.Lua
  lua_settings.runtime = lua_settings.runtime or {}
  lua_settings.runtime.version = 'LuaJIT'
  lua_settings.runtime.path = { 'lua/?.lua', 'lua/?/init.lua' }
  lua_settings.workspace = lua_settings.workspace or {}
  lua_settings.workspace.library = libraries
end

function M.setup()
  -- 上游 lua_ls 默认按「Lua 配置 > formatter 配置 > .git」分组查找，
  -- 父级 nvim 的 .luarc.json 会因此压过 vendor 子仓里更近的 .git
  -- 所有 marker 设为同优先级后，按最近祖先选 root
  vim.lsp.config('lua_ls', {
    root_markers = { root_markers },
    root_dir = root_dir,
    single_file_support = false,
    before_init = inject_project_libraries,
  })
end

return M
