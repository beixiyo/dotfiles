-- 专用「跟随调用方目录」浮动终端：供文件树等处「在此目录开终端」复用
-- 语义不是 toggle：每次调用把同一终端切到目标 cwd（保留会话）；关闭/隐藏由终端内 q / <esc> 负责

---@class tools.term
local M = {}

local term     ---@type table?  toggleterm Terminal 实例（交互 shell，跟随 cwd）
local term_dir ---@type string? 当前 cwd
local run_term ---@type table?  一次性命令的浮窗终端（与交互 shell 分开）

-- toggleterm 是 opt 懒加载插件，未加载时直接 require 会失败；经 pack.loader 强制加载
-- （幂等，会跑其 setup 注册命令，不影响其余 <leader>t* 键位）
---@return table? Terminal  加载失败返回 nil
local function get_terminal_mod()
  local ok, mod = pcall(require, 'toggleterm.terminal')
  if ok then return mod end

  for _, s in ipairs(_G.Pack and _G.Pack.specs or {}) do
    if s.id == 'toggleterm' then
      require('pack.loader').load(s)
      break
    end
  end

  ok, mod = pcall(require, 'toggleterm.terminal')
  return ok and mod or nil
end

-- 终端 buffer 内键位：jk / <esc> 回 normal；normal 下 q / <esc> 隐藏本终端
-- （专用 hidden 终端不归 :ToggleTerm 编号管理，故全局 q→:ToggleTerm 对它无效，需自绑）
---@param t table  toggleterm Terminal
local function set_term_keys(t)
  local o = { buffer = t.bufnr, silent = true }
  vim.keymap.set('t', 'jk', [[<C-\><C-n>]], o)
  vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], o)
  vim.keymap.set('n', 'q', function() t:close() end, o)
  vim.keymap.set('n', '<esc>', function() t:close() end, o)
end

-- 在 dir 打开/切换专用浮动终端，cwd 跟随调用方（非 toggle）
--   * 未创建 → 在该目录新建浮窗终端
--   * 已存在但目录变了 → cd 到新目录（保留会话）
--   * 已存在且同目录 → 直接聚焦
---@param dir string  目标工作目录
function M.open_at(dir)
  if not dir or dir == '' then return end

  local mod = get_terminal_mod()
  if not mod then
    vim.notify('tools.term: failed to load toggleterm', vim.log.levels.ERROR)
    return
  end

  local alive = term and term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr)

  if not alive then
    -- fnameescape 防 toggleterm 内部 fn.expand 把 $ / glob / 空格 当元字符
    term = mod.Terminal:new({
      dir = vim.fn.fnameescape(dir),
      direction = 'float',
      hidden = true,
      on_open = set_term_keys,
    })
    term_dir = dir
    term:open()
    return
  end

  if not term:is_open() then term:open() end

  if term_dir ~= dir then
    -- shellescape 正确处理空格 / $ 等（toggleterm 自带 change_dir 的 `cd %s` 不转义会断）
    term:send('cd ' .. vim.fn.shellescape(dir))
    term:clear()
    term_dir = dir
  end

  term:focus()
end

-- 在专用浮窗里跑一条一次性命令（与交互 shell 分开，保留输出便于看结果/退出码）
---@param cmd string[]  完整 argv
---@param dir? string   工作目录
function M.run(cmd, dir)
  if not cmd or #cmd == 0 then return end

  local mod = get_terminal_mod()
  if not mod then
    vim.notify('tools.term: failed to load toggleterm', vim.log.levels.ERROR)
    return
  end

  -- toggleterm 的 cmd 是 shell 字符串，逐段 shellescape 拼接，兼容空格/特殊字符
  local cmdstr = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), ' ')

  if run_term then pcall(function() run_term:shutdown() end) end
  run_term = mod.Terminal:new({
    cmd = cmdstr,
    dir = dir and vim.fn.fnameescape(dir) or nil,
    direction = 'float',
    hidden = true,
    close_on_exit = false, -- 跑完保留输出（覆盖全局 close_on_exit=true）
    on_open = set_term_keys,
  })
  run_term:open()
end

return M
