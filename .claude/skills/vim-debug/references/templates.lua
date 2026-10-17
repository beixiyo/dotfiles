-- vim-debug 模板：dump 快照 + ground truth + arm 抓瞬态事件
-- 验证环境：nvim 0.13.0-dev-1617（2026-10-17），dump / arm / disarm / ground_truth 均在 headless 下端到端跑过
-- API 可能变化，复制后先用 headless 探针跑通再用于排查（注意 `nvim -l` 脚本结束即退出，需 vim.wait 才能等到 defer）
-- 约定：`myplug` / `MyPlug` 替换为被调试插件名

local LOG_BASE = '/tmp/myplug-debug'

--- 哨兵应由被修改的模块导出（改代码就改这串），dump 读它；模块没重新加载则版本对不上
local function sentinel()
  local ok, mod = pcall(require, 'myplug')
  return ok and type(mod) == 'table' and mod.SENTINEL or '<no SENTINEL>'
end


--- 不经 shell 执行外部命令。不带 text，保留原始字节（text=true 会把 \r\n 规范成 \n）
--- @return { code: integer, stdout: string, stderr: string }
local function exec(cmd)
  local r = vim.system(cmd):wait()
  return { code = r.code, stdout = r.stdout or '', stderr = r.stderr or '' }
end

--- 外部命令输出的哈希；失败时返回错误描述，不对错误信息算哈希
local function hash_of_cmd(cmd)
  local r = exec(cmd)
  if r.code ~= 0 then
    return ('<error code=%d: %s>'):format(r.code, vim.trim(r.stderr))
  end
  return vim.fn.sha256(r.stdout)
end

local function read_file(path)
  local fh = io.open(path, 'rb')
  if not fh then return nil end
  local s = fh:read('*a')
  fh:close()
  return s
end

--- 字节级可见化：vim.inspect 只转义控制字符，BOM / 零宽字符需 strtrans
--- strtrans 会把 \n 显示成 ^@（NUL 的写法），先转成字面 \n 避免误导
local function visible(s)
  return vim.inspect(vim.fn.strtrans((s:gsub('\n', '\\n'))))
end


--- Ground truth：磁盘 / git 字节与运行时对比（不经 shell，不依赖 md5sum）
--- git show 是 blob 原始字节，不经 smudge / autocrlf；cat-file --filters 才对应工作区行为
--- @param add fun(s: string)
--- @param path string 文件绝对路径
local function ground_truth(add, path)
  local bytes = read_file(path)
  if not bytes then
    add('file     = <missing> ' .. path)
    return
  end

  add('file     = ' .. vim.trim(exec({ 'file', path }).stdout))
  add('sha256   = ' .. vim.fn.sha256(bytes))
  add('head-16  = ' .. visible(bytes:sub(1, 16)))
  add('head-hex = ' .. bytes:sub(1, 16):gsub('.', function(c) return ('%02x '):format(c:byte()) end))

  local root = vim.fs.root(path, '.git')
  if not root then
    add('git      = <not in a git repo>')
    return
  end

  local rel = vim.fs.relpath(root, path)
  add('git blob = ' .. hash_of_cmd({ 'git', '-C', root, 'show', 'HEAD:' .. rel }))
  add('git filt = ' .. hash_of_cmd({ 'git', '-C', root, 'cat-file', '--filters', 'HEAD:' .. rel }))
end


--- 采一份快照。每次 'w' 覆盖，多份对比用 tag 分文件
--- @param tag string|nil
--- @param extend fun(add: fun(s: string))|nil 按需追加维度
local function dump(tag, extend)
  local log = (tag and tag ~= '')
      and (LOG_BASE .. '.' .. tag .. '.log') or (LOG_BASE .. '.log')
  local out = {}
  local function add(s) out[#out + 1] = s end

  add('SENTINEL: ' .. sentinel())
  add('TS:  ' .. os.date('%Y-%m-%d %H:%M:%S'))
  add('TAG: ' .. (tag or '<none>'))
  add('MODE: ' .. vim.inspect(vim.api.nvim_get_mode()))

  if extend then
    local ok, err = xpcall(extend, debug.traceback, add)
    if not ok then add('EXTEND ERROR: ' .. tostring(err)) end
  end

  local fh = assert(io.open(log, 'w'))
  fh:write(table.concat(out, '\n'))
  fh:close()

  -- 调试工具不能静默失败：pedit 失败（如预览 buffer 被改动 E37）要报出来
  local ok, err = pcall(vim.cmd, 'silent botright pedit ' .. vim.fn.fnameescape(log))
  if not ok then vim.notify('pedit failed: ' .. tostring(err), vim.log.levels.WARN) end
  vim.notify('dumped ' .. log)
end

vim.api.nvim_create_user_command('MyPlugDump', function(opts)
  dump(opts.args, function(add)
    -- 示例维度：tab 内窗口及关键 win-local 选项，以及各窗口 diff 的全局副本（污染排查见 case 文件）
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(w)
      add(('win %d buf %d ft=%s diff=%s(global copy=%s) scb=%s fdm=%s'):format(
        w, buf, vim.bo[buf].filetype, vim.wo[w].diff,
        vim.api.nvim_get_option_value('diff', { scope = 'global', win = w }),
        vim.wo[w].scrollbind, vim.wo[w].foldmethod))
    end

    -- 示例：对当前 buffer 对应的磁盘文件做 ground truth
    local path = vim.api.nvim_buf_get_name(0)
    if path ~= '' then ground_truth(add, path) end
  end)
end, { nargs = '?' })


--- Arm：等某事件发生后再 dump。:MyPlugArm [event] [tag]
--- 不能指定 pattern；重复 arm 会替换上一次（同 augroup clear=true），不会互相删除
local ARM = 'MyPlugArmDebug'

vim.api.nvim_create_user_command('MyPlugArm', function(opts)
  local args = vim.split(opts.args, '%s+', { trimempty = true })
  local event, tag = args[1] or 'CmdlineEnter', args[2]

  local aug = vim.api.nvim_create_augroup(ARM, { clear = true })
  vim.api.nvim_create_autocmd(event, {
    group = aug,
    once = true, -- 触发一次后 autocmd 自动移除，不需要在 defer 里删 augroup（会误删新一轮 arm）
    callback = function()
      -- defer 是等其它 handler 的时间窗口，不是同步保证；慢的异步回调可能超过 200ms
      vim.defer_fn(function()
        vim.cmd('MyPlugDump' .. (tag and (' ' .. tag) or ''))
      end, 200)
    end,
  })
  vim.notify('armed on ' .. event .. (tag and (' -> tag=' .. tag) or ''))
end, { nargs = '*' })

--- 事件一直不来时手动撤销，避免长期挂着
vim.api.nvim_create_user_command('MyPlugDisarm', function()
  pcall(vim.api.nvim_del_augroup_by_name, ARM)
  vim.notify('disarmed')
end, {})

-- 若 `:` 本身就是 bug 触发源，arm 是默认方案；也可挂 buf-local 键位
-- vim.keymap.set('n', 'gD', '<Cmd>MyPlugDump<CR>', { buffer = buf, silent = true })
