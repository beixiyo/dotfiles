local path    = require('vv-utils.path')
local icons   = require('vv-icons')
local actions = require('plugins.specs.ui.lualine.actions')

local ok_dev, devicons = pcall(require, 'nvim-web-devicons')
local lualine_utils = require('lualine.utils.utils')

local M = {}

--- statusline 里 % 是格式码，外部文本必须转义以避免 E539
---@param s string?
---@return string
local function stl_escape(s)
  if type(s) ~= 'string' or s == '' then return '' end
  return (s:gsub('%%', '%%%%'))
end

-- 接受 function（仅左键）或 {l=..., r=..., m=...}
local function on_click(handlers)
  if type(handlers) == 'function' then handlers = { l = handlers } end
  return function(_, button)
    local fn = handlers[button]
    if fn then fn() end
  end
end

local hl_color = require('vv-utils.hl').get_fg

-- LSP 噪音过滤：配置文件、纯文本不值得显示客户端状态
local lsp_hidden_fts = {
  json = true, jsonc = true, yaml = true, yml = true, toml = true,
  ini = true, dosini = true, conf = true, config = true,
  gitconfig = true, gitignore = true, gitattributes = true,
  sshconfig = true, properties = true, dotenv = true,
  md = true, markdown = true, txt = true,
}

local function lsp_should_show()
  if vim.bo.buftype ~= '' then return false end
  if vim.api.nvim_buf_get_name(0) == '' and (vim.bo.filetype == nil or vim.bo.filetype == '') then
    return false
  end
  return not lsp_hidden_fts[vim.bo.filetype]
end

local function lsp_progress()
  local ok, msgs = pcall(vim.lsp.util.get_progress_messages)
  if ok and type(msgs) == 'table' and #msgs > 0 then
    local m = msgs[1] or {}
    local parts = {}
    if m.name or m.title then table.insert(parts, stl_escape(m.name or m.title)) end
    if m.message and m.message ~= '' then table.insert(parts, stl_escape(m.message)) end
    if m.percentage then table.insert(parts, tostring(m.percentage) .. '%%') end
    return table.concat(parts, ' ')
  end
  return stl_escape((type(vim.lsp.status) == 'function' and vim.lsp.status()) or '')
end

local function lsp_clients()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if vim.tbl_isempty(clients) then return '' end
  local names = {}
  for _, c in ipairs(clients) do
    if c.name and c.name ~= '' and c.name ~= 'copilot' then
      table.insert(names, stl_escape(c.name))
    end
  end
  if #names == 0 then return '' end
  table.sort(names)
  local max = 2
  if #names > max then
    return names[1] .. ',' .. names[2] .. ' +' .. (#names - max)
  end
  return table.concat(names, ',')
end

local function buf_devicon()
  if not ok_dev then return '' end
  local file = vim.api.nvim_buf_get_name(0)
  local name = vim.fn.fnamemodify(file, ':t')
  return devicons.get_icon(name, vim.fn.fnamemodify(file, ':e'), { default = true }) or ''
end

local function format_hl(component, text, hl_group)
  text = text:gsub('%%', '%%%%')
  if not hl_group or hl_group == '' then return text end
  component.hl_cache = component.hl_cache or {}
  local cached = component.hl_cache[hl_group]
  if not cached then
    local gui = vim.tbl_filter(function(x) return x end, {
      lualine_utils.extract_highlight_colors(hl_group, 'bold') and 'bold',
      lualine_utils.extract_highlight_colors(hl_group, 'italic') and 'italic',
    })
    cached = component:create_hl({
      fg = lualine_utils.extract_highlight_colors(hl_group, 'fg'),
      gui = #gui > 0 and table.concat(gui, ',') or nil,
    }, 'LV_' .. hl_group)
    component.hl_cache[hl_group] = cached
  end
  return component:format_hl(cached) .. text .. component:get_default_hl()
end

-- ColorScheme 切换后，缓存的高亮名会指向旧色号
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('LualineHlCacheClear', { clear = true }),
  callback = function()
    for _, section in pairs(package.loaded['lualine'] and require('lualine').get_config().sections or {}) do
      if type(section) == 'table' then
        for _, comp in ipairs(section) do
          if type(comp) == 'table' then comp.hl_cache = nil end
        end
      end
    end
  end,
})

function M.mode() return 'mode' end

-- lualine 内置 "branch" 走 expand('%:p:h')，在 nofile/URL-scheme buffer（vv-explorer、dashboard）
-- 上解析不到 .git → globalstatus 下分支会消失。
-- 统一用 lualine 的 find_git_dir：真实文件用所在目录，虚拟 buffer 退回 cwd
function M.branch()
  local git_branch = require('lualine.components.branch.git_branch')
  local sep = package.config:sub(1, 1)

  local function read_head(git_dir)
    local f = io.open(git_dir .. sep .. 'HEAD')
    if not f then return '' end
    local head = f:read() or ''
    f:close()
    return head:match('ref: refs/heads/(.+)$') or head:sub(1, 7)
  end

  return {
    function()
      local bufname = vim.api.nvim_buf_get_name(0)
      local virtual = vim.bo.buftype ~= '' or bufname == '' or bufname:match('^%a[%w_%-]*://') ~= nil
      local dir = virtual and vim.fn.getcwd() or vim.fn.expand('%:p:h')
      local git_dir = git_branch.find_git_dir(dir)
      return git_dir and read_head(git_dir) or ''
    end,
    icon = '',
    on_click = on_click({ l = actions.quick_commit_push, r = actions.open_git_log }),
  }
end

-- 项目根缓存：get_root 是未缓存的向上 vim.fs.find 文件系统遍历，而 lualine
-- 在每次重绘都会调用 cond/render。某个 buffer 的项目根在编辑期间是稳定的，
-- 故按 bufnr 缓存，仅在 cwd 变化（DirChanged）或 buffer 改名（BufFilePost）时失效。
local root_cache = {}
vim.api.nvim_create_autocmd({ 'DirChanged', 'BufFilePost' }, {
  group = vim.api.nvim_create_augroup('LualineRootDirCacheClear', { clear = true }),
  callback = function() root_cache = {} end,
})

function M.root_dir()
  local icon = '󱉭 '
  -- 缓存值：string 显示 / false 不显示（root == cwd）/ nil 表示未计算
  local function compute()
    local cwd, root = path.get_cwd(), path.get_root()
    if root == cwd then return false end
    return vim.fs.basename(root)
  end

  local function get()
    local buf = vim.api.nvim_get_current_buf()
    local v = root_cache[buf]
    if v == nil then
      v = compute()
      root_cache[buf] = v
    end
    return v
  end

  return {
    function()
      local v = get()
      return (icon .. ' ') .. (type(v) == 'string' and v or '')
    end,
    cond = function() return type(get()) == 'string' end,
    color = function() return { fg = hl_color('Special') } end,
    on_click = on_click(actions.open_root_picker),
  }
end

function M.diagnostics()
  return {
    'diagnostics',
    symbols = {
      error = icons.diagnostics_error .. ' ',
      warn  = icons.diagnostics_warn  .. ' ',
      info  = icons.diagnostics_info  .. ' ',
      hint  = icons.diagnostics_hint  .. ' ',
    },
    on_click = on_click({ l = actions.open_diagnostics, r = actions.next_diagnostic }),
  }
end

function M.pretty_path()
  local opts = {
    modified_hl    = 'MatchParen',
    directory_hl   = '',
    filename_hl    = 'Bold',
    modified_sign  = '',
    readonly_icon  = ' 󰌾 ',
    length         = 3,
  }

  -- 按 bufname 缓存昂贵的 get_root（未缓存的向上 fs.find），避免每次重绘都遍历文件系统；
  -- get_cwd 极廉价（仅 uv.cwd），每次刷新以反映 :cd 后的相对路径截断。
  local cache = { name = nil, root = nil }
  local render = function(self)
    local file = vim.fn.expand('%:p') --[[@as string]]
    if file == '' then return '' end
    file = path.norm(file)

    local key = vim.api.nvim_buf_get_name(0)
    if cache.name ~= key then
      cache.name, cache.root = key, path.get_root()
    end

    local root, cwd, norm = cache.root, path.get_cwd(), file

    if vim.fn.has('win32') == 1 then
      norm = norm:lower(); root = root:lower(); cwd = cwd:lower()
    end

    if norm:find(cwd, 1, true) == 1 then
      file = file:sub(#cwd + 2)
    elseif norm:find(root, 1, true) == 1 then
      file = file:sub(#root + 2)
    end

    local sep = package.config:sub(1, 1)
    local parts = vim.split(file, '[\\/]')
    if #parts > opts.length then
      parts = { parts[1], '…', table.unpack(parts, #parts - opts.length + 2, #parts) }
    end

    if vim.bo.modified then
      parts[#parts] = format_hl(self, parts[#parts] .. opts.modified_sign, opts.modified_hl)
    else
      parts[#parts] = format_hl(self, parts[#parts], opts.filename_hl)
    end

    local dir = ''
    if #parts > 1 then
      dir = table.concat({ table.unpack(parts, 1, #parts - 1) }, sep)
      dir = format_hl(self, dir .. sep, opts.directory_hl)
    end

    local readonly = vim.bo.readonly and format_hl(self, opts.readonly_icon, opts.modified_hl) or ''

    local macro = ''
    local reg = vim.fn.reg_recording()
    if reg ~= '' then
      macro = format_hl(self, '  @' .. reg, 'DiagnosticError')
    end

    return dir .. parts[#parts] .. readonly .. macro
  end

  return {
    render,
    on_click = on_click(actions.copy_abs_path),
  }
end

function M.lsp()
  return {
    function()
      if not lsp_should_show() then return '' end
      local icon = buf_devicon()
      local prefix = icon ~= '' and (icon .. ' ') or ''
      local progress = lsp_progress()
      if progress ~= '' then return prefix .. progress end
      local clients_str = lsp_clients()
      if clients_str ~= '' then return prefix .. clients_str end
      return prefix .. 'NoLSP'
    end,
    cond = lsp_should_show,
    color = function() return { fg = hl_color('Special') } end,
    on_click = on_click({ l = actions.open_lsp_info, r = actions.open_mason }),
  }
end

local function noice_component(api_key, hl_group)
  return {
    function() return stl_escape(require('noice').api.status[api_key].get()) end,
    cond = function()
      return package.loaded['noice'] and require('noice').api.status[api_key].has()
    end,
    color = function() return { fg = hl_color(hl_group) } end,
  }
end

function M.noice_command() return noice_component('command', 'Statement') end

function M.dap()
  return {
    function() return icons.dap_status .. ' ' .. require('dap').status() end,
    cond = function() return package.loaded['dap'] and require('dap').status() ~= '' end,
    color = function() return { fg = hl_color('Debug') } end,
    on_click = on_click(actions.toggle_dap_repl),
  }
end

function M.diff()
  return {
    'diff',
    symbols = {
      added    = icons.git_added    .. ' ',
      modified = icons.git_modified .. ' ',
      removed  = icons.git_removed  .. ' ',
    },
    source = function()
      local g = vim.b.gitsigns_status_dict
      if g then return { added = g.added, modified = g.changed, removed = g.removed } end
    end,
    on_click = on_click({ l = actions.open_git_status, r = actions.blame_line }),
  }
end

function M.progress()
  return {
    'progress',
    separator = ' ',
    padding = { left = 1, right = 0 },
    on_click = on_click({ l = actions.center_line, r = actions.go_top }),
  }
end

function M.location()
  return {
    function() return actions.visual_range() or '%l' end,
    padding = { left = 0, right = 1 },
    on_click = on_click(actions.copy_abs_path_line),
  }
end

function M.clock()
  return {
    function() return icons.clock .. ' ' .. os.date('%R') end,
    on_click = on_click(actions.copy_datetime),
  }
end

return M
