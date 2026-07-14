-- ╭─────────────────────────────────────────────────────╮
-- │                    字体配置                          │
-- ╰─────────────────────────────────────────────────────╯
-- 字体与斜体说明：
-- - VSCode/Cursor 用系统文本栈，可合成斜体；终端 Neovim 通过 SGR 转义请求斜体
-- - Nerd Font（如 Maple Mono NF）很多没有真正 Italic 字型，只靠 WezTerm 合成斜体
-- - 不显式写 italic 规则时，某些环境（尤其 Windows + Neovim）下斜体不生效
-- 解决：显式添加 font_rules，对斜体使用 style = 'Italic'，让 WezTerm 合成斜体

local wezterm = require('wezterm')

local M = {}

local is_macos = wezterm.target_triple:find('darwin') ~= nil

function M.apply(config)
  config.font = wezterm.font_with_fallback({
    'Maple Mono NF',
    '等线',       -- 中文
    'monospace',  -- Emoji
  })

  -- 注：tmux 顶栏数字圆圈（Nerd Font MDI，如 󰬺 U+F0B3A）在 WezTerm 下偏小，
  -- 是 Maple Mono NF 把该字形按单格 advance=8px 画的，WezTerm 忠实渲染、无内建
  -- Nerd Font 拉伸（不同于 Ghostty/Kitty）。cell_widths / allow_square 均已实测无效，
  -- 终端侧无解，故不再保留相关配置。

  config.font_rules = {
    { intensity = 'Normal', italic = true, font = wezterm.font_with_fallback({ { family = 'Maple Mono NF', style = 'Italic' }, '等线', 'monospace' }) },
    { intensity = 'Bold',   italic = true, font = wezterm.font_with_fallback({ { family = 'Maple Mono NF', weight = 'Bold', style = 'Italic' }, '等线', 'monospace' }) },
    { intensity = 'Half',   italic = true, font = wezterm.font_with_fallback({ { family = 'Maple Mono NF', style = 'Italic' }, '等线', 'monospace' }) },
  }

  config.font_size = is_macos and 12 or 10

  -- 字体渲染与对比度提升
  -- freetype_load_target: Normal (默认/有 hinting) | Light (较软) | HorizontalLcd (锐利 LCD 子像素)
  config.freetype_load_target   = 'HorizontalLcd'
  config.freetype_render_target = 'HorizontalLcd'
end

return M
