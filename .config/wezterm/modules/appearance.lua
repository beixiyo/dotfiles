-- ╭─────────────────────────────────────────────────────╮
-- │            外观：主题 / tab bar / 背景              │
-- ╰─────────────────────────────────────────────────────╯

local wezterm = require('wezterm')

local M = {}

function M.apply(config)
  -- 终端配色
  config.color_scheme = 'Catppuccin Mocha'

  -- 光标
  -- 'SteadyBlock' | 'BlinkingBlock' | 'SteadyUnderline' | 'BlinkingUnderline' | 'SteadyBar' | 'BlinkingBar'
  config.default_cursor_style = 'SteadyBlock'
  config.colors = {
    cursor_bg = '#52ad99',
  }

  -- 窗口装饰：仅保留调整大小的边框
  config.window_decorations = 'RESIZE'

  -- Tab bar
  config.use_fancy_tab_bar              = false
  config.enable_tab_bar                 = true
  config.show_tab_index_in_tab_bar      = false
  config.hide_tab_bar_if_only_one_tab   = false
  config.show_new_tab_button_in_tab_bar = false

  -- 窗口 padding（确保背景色一致）
  config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

  -- 透明度与模糊
  config.macos_window_background_blur = 7
  config.window_background_opacity    = 0.9

  -- 非活动窗格不变暗
  config.inactive_pane_hsb = {
    saturation = 1.0,
    brightness = 1.0,
  }

  -- 自定义 tab bar 渲染（控制 tab 间距）
  wezterm.on('format-tab-title', function(tab, _tabs, _panes, _config, _hover, max_width)
    local edge_background = '#0b0022'
    local background = tab.is_active and '#1b1032' or '#0b0022'
    local foreground = tab.is_active and '#fff' or '#777'

    local title = tab.active_pane.title
    if #title > max_width then
      title = string.sub(title, 1, max_width - 3) .. '...'
    end

    return {
      { Background = { Color = edge_background } },
      { Text = ' ' },
      { Background = { Color = background } },
      { Foreground = { Color = foreground } },
      { Text = title },
      { Background = { Color = edge_background } },
      { Text = ' ' },
    }
  end)
end

return M
