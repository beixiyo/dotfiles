-- 声明式懒加载：把 spec.event / ft / cmd / keys 注册为首次触发加载钩子
-- keys 实现与 lazy.nvim 一致：装 expr=true 占位 keymap，触发时 del 占位 + load + 重装真实 rhs + feedkeys <Ignore>lhs
-- 好处：rhs 走完整 keymap 解析，operator-pending/count/motion 行为正确；支持 ft/expr/nowait/remap/silent/<Nop>
local M = {}

-- 默认仅 normal 模式（对齐 lazy.nvim）：避免无 mode 条目的 x/o 覆盖同 lhs 的显式 mode='v' 条目
-- 需要 visual/operator-pending 的条目应显式声明 mode（如 flash.lua）
local default_modes = { 'n' }

-- 归一化 keys 条目：字符串 → { lhs }；table 保持原样
local function normalize_entry(entry)
  if type(entry) == 'string' then return { entry } end
  return entry
end

-- 从条目提取 vim.keymap.set 认的 opts 字段
local function collect_set_opts(entry)
  local opts = {}
  for _, k in ipairs({ 'desc', 'noremap', 'remap', 'nowait', 'silent', 'expr' }) do
    if entry[k] ~= nil then opts[k] = entry[k] end
  end
  return opts
end

local function is_nop(rhs)
  return type(rhs) == 'string' and (rhs == '' or rhs:lower() == '<nop>')
end

-- 装"真实" keymap：插件加载后由 trigger 或 ft autocmd 调
local function set_real(entry, buf)
  local rhs = entry[2]
  if rhs == nil or rhs == false then return end -- 没 rhs 留给插件自己绑
  local modes = entry.mode or default_modes
  if type(modes) == 'string' then modes = { modes } end
  local opts = collect_set_opts(entry)
  opts.buffer = buf
  for _, mode in ipairs(modes) do
    vim.keymap.set(mode, entry[1], rhs, opts)
  end
end

-- 装触发型 keymap（expr=true 占位）：首次按下 → del 占位 → load → 装真 rhs → feedkeys 重放
local function set_trigger(entry, do_load, buf)
  local lhs = entry[1]
  local rhs = entry[2]

  -- <Nop> / 空串特殊：直接设真 keymap，不触发加载
  if is_nop(rhs) then
    set_real(entry, buf)
    return
  end

  local modes = entry.mode or default_modes
  if type(modes) == 'string' then modes = { modes } end

  local fired = false
  local function trigger()
    if fired then return '' end
    fired = true
    -- 先 del 所有占位 mapping，避免 feedkeys 递归触发
    for _, m in ipairs(modes) do
      pcall(vim.keymap.del, m, lhs, buf and { buffer = buf } or nil)
    end
    do_load()
    -- 重装真实 keymap（如果 entry 提供了 rhs）
    set_real(entry, buf)
    -- <Ignore> 前缀让 lhs 重新走 keymap 解析，而不是进入光标
    local effective = lhs
    local feed = vim.api.nvim_replace_termcodes('<Ignore>' .. effective, true, true, true)
    vim.api.nvim_feedkeys(feed, 'i', false)
    return ''
  end

  for _, mode in ipairs(modes) do
    -- abbreviation 模式额外追加 <C-]> 才能真正触发（见 lazy.nvim handler/keys.lua）
    local kopts = {
      expr = true,
      desc = entry.desc,
      nowait = entry.nowait,
      silent = entry.silent,
      buffer = buf,
    }
    vim.keymap.set(mode, lhs, trigger, kopts)
  end
end

-- 注册一个 spec 的所有触发器
-- do_load: 闭包，调用后真正加载插件（幂等）
function M.register(spec, do_load)
  local name = spec.id or 'unnamed'
  local group = vim.api.nvim_create_augroup(
    'PackLazy_' .. name:gsub('[^%w]', '_'),
    { clear = true }
  )

  -- event：首次事件触发时加载
  -- 支持 lazy.nvim 风格："BufReadPost *.json" → event + pattern
  if spec.event then
    local raw = type(spec.event) == 'string' and { spec.event } or spec.event
    for _, s in ipairs(raw) do
      local ev, pat = s:match('^(%S+)%s+(.+)$')
      if not ev then ev = s end
      vim.api.nvim_create_autocmd(ev, {
        group = group, once = true, pattern = pat, callback = do_load,
      })
    end
  end

  -- ft：FileType 匹配时加载
  if spec.ft then
    vim.api.nvim_create_autocmd('FileType', {
      group = group, pattern = spec.ft, once = true, callback = do_load,
    })
  end

  -- cmd：注册占位 user command，首次调用时加载并结构化重放
  if spec.cmd then
    for _, c in ipairs(spec.cmd) do
      vim.api.nvim_create_user_command(c, function(opts)
        pcall(vim.api.nvim_del_user_command, c)
        do_load()
        vim.api.nvim_cmd({
          cmd = c,
          args = opts.fargs,
          bang = opts.bang,
          mods = opts.smods,
          range = opts.range > 0 and { opts.line1, opts.line2 } or nil,
        }, {})
      end, { nargs = '*', range = true, bang = true })
    end
  end

  -- keys：装触发型 keymap；ft 限定的走 FileType autocmd 做 buffer-local 绑定
  -- spec.keys 可以是 table，也可以是 function（延迟构造，让 desc 等字段 lazy require icons 等依赖）
  local keys = spec.keys
  if type(keys) == 'function' then
    local ok, ret = pcall(keys, spec)

    if not ok then
      vim.notify('[pack] ' .. (spec.id or '?') .. ' keys() 求值失败: ' .. tostring(ret), vim.log.levels.ERROR)
      keys = nil
    else
      keys = ret
    end
  end

  if keys then
    for _, raw in ipairs(keys) do
      local entry = normalize_entry(raw)
      if type(entry[1]) == 'string' then
        if entry.ft then
          local fts = type(entry.ft) == 'string' and { entry.ft } or entry.ft
          vim.api.nvim_create_autocmd('FileType', {
            group = group, pattern = fts,
            callback = function(ev) set_trigger(entry, do_load, ev.buf) end,
          })
        else
          set_trigger(entry, do_load, nil)
        end
      end
    end
  end
end

-- 判断 spec 是否声明了任何触发器
function M.has_triggers(spec)
  return spec.event ~= nil or spec.ft ~= nil or spec.cmd ~= nil or spec.keys ~= nil
  -- 注：keys 是 function 也算触发器（延迟到 register 时才求值）
end

return M
