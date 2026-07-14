-- im-select：插入模式自动切换输入法
-- 三种平台 + 插入时根据字符语境自动选中/英文
local is_wsl = vim.fn.has('wsl') == 1
local is_mac = vim.fn.has('mac') == 1
local is_win = vim.fn.has('win32') == 1

local bin_name, download_tip
if is_mac then
  bin_name = 'macism'
  download_tip = 'https://github.com/laishulu/macism'
elseif is_win or is_wsl then
  bin_name = 'im-select.exe'
  download_tip = 'https://github.com/daipeihust/im-select（WSL 需将 Windows 侧 exe 加入 PATH）'
else
  bin_name = 'fcitx5-remote'
  download_tip = '通过发行版包管理器安装 fcitx5（提供 fcitx5-remote）'
end

---@type PackSpec
return {
  desc = '输入法自动切换',
  url = 'https://github.com/hughfenghen/fenghen-im-select.nvim',
  main = 'im_select.init',

  cond = function()
    if vim.fn.executable(bin_name) == 1 then return true end
    vim.schedule(function()
      vim.notify(
        ('未检测到 %s，未注册 im-select 插件（不会下载）。\n可安装/下载：%s'):format(bin_name, download_tip),
        vim.log.levels.WARN,
        { title = 'im-select' }
      )
    end)
    return false
  end,

  config = function()
    local im_select = require('im_select.init')
    ---@type im_select.Config
    local opts = {}
    local native_im, default_im

    if is_mac then
      opts.im_select_get_im_cmd = { 'macism' }
      opts.ImSelectSetImCmd = function(key) return { 'macism', key } end
      native_im = 'com.tencent.inputmethod.wetype.pinyin'
      default_im = 'com.apple.keylayout.ABC'
    elseif is_win or is_wsl then
      opts.im_select_get_im_cmd = { 'im-select.exe' }
      opts.ImSelectSetImCmd = function(key) return { 'im-select.exe', key } end
      native_im = '2052'
      default_im = '1033'
    else
      opts.im_select_get_im_cmd = { 'fcitx5-remote' }
      opts.ImSelectSetImCmd = function(key)
        if key == '1' then return { 'fcitx5-remote', '-c' }
        elseif key == '2' then return { 'fcitx5-remote', '-o' } end
      end
      native_im = '2'
      default_im = '1'
    end

    opts.im_select_default = default_im

    opts.insert_enter_strategies = {
      function(ctx)
        local nr = ctx.charcode_before or ctx.charcode_after or 0
        if nr >= 0x4E00 and nr <= 0x9FFF or nr >= 0x3000 and nr <= 0x303F or nr >= 0xFF00 and nr <= 0xFFEF then
          return native_im
        end
      end,
      function(ctx)
        local ch = ctx.char_before or ctx.char_after or ''
        if ch:match('[a-zA-Z]') then return default_im end
      end,
      function(ctx)
        local valid_types = {
          typescript = true, typescriptreact = true, javascript = true, javascriptreact = true,
          lua = true, html = true, css = true, python = true, go = true, rust = true,
        }
        if valid_types[ctx.filetype] then
          if ctx.is_inside_comment then return native_im else return default_im end
        end
      end,
      function() return default_im end,
    }

    opts.im_select_switch_timeout = 100
    opts.im_select_enable_focus_events = 1
    opts.im_select_enable_cmd_line = 1

    im_select.setup(opts)
  end,
}
