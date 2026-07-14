-- Pretty Dark 主题调色板（自包含，不从 storm 继承）
-- 设计规格详见 vendors/tokyonight.nvim/README.md
-- 用法：tokyonight.load({ style = "pretty_dark" })

---@class Palette
local ret = {
  -- ── 背景梯度（warm dark：黄棕底）
  bg           = "#191816", -- 主背景
  bg_dark      = "#141311", -- sidebar / popup（比 bg 略深，保持暖调）
  bg_dark1     = "#0f0e0c", -- 最深档（float / 深层弹窗）
  bg_highlight = "#23262c", -- 当前行高亮

  -- ── 蓝色系（由深到浅）
  blue         = "#4aa5f0", -- 函数 / 方法名（主色，不改）
  blue0        = "#2d5a8f", -- 搜索底色 / visual blend 源（需要偏暗才能当 bg 用）
  blue1        = "#4dc4ff", -- 亮蓝（边框高亮、特殊强调）
  blue2        = "#5ab0f7", -- 中亮蓝（与 blue 微分层）
  blue5        = "#7fd4ff", -- 浅蓝（punctuation）
  blue6        = "#b4ecff", -- 最浅（markup / 特殊符号）
  blue7        = "#334d70", -- 暗蓝（border / diff change 底）

  -- ── 青绿系
  cyan         = "#42b3c2", -- 偏蓝的青
  teal         = "#6dc7a8", -- 偏绿的青（diagnostic hint 色）

  -- ── 绿色系
  green        = "#98c379", -- 字符串
  green1       = "#7ec06c", -- 深绿（微分层）
  green2       = "#a5e075", -- 亮绿（git.add）

  -- ── 紫 / 品红系
  magenta      = "#c678dd", -- 关键字紫（斜体）
  magenta2     = "#de73ff", -- 亮紫
  purple       = "#a787d0", -- 蓝紫（与 magenta 分化）

  -- ── 暖色系
  orange       = "#d19a66", -- 数字 / 属性
  red          = "#e05561", -- 红
  red1         = "#c24038", -- 深红（git.delete 血色）
  yellow       = "#e5c07b", -- 真黄（原 #d18f52 偏棕，改亮对齐 git.change）

  -- ── 辅助色
  comment        = "#7f848e",
  fg             = "#c2c2c2", -- 主前景
  fg_dark        = "#a8a8a8", -- sidebar 前景（比 fg 略暗，保持层次）
  fg_gutter      = "#495162", -- 行号
  dark3          = "#3f4451",
  dark5          = "#7f848e",
  terminal_black = "#191815",
  border         = "#31312d", -- 分屏 / 浮窗边框（覆盖 init.lua 默认的 blend(bg, 0.8, #000)，避免与主背景融为一体）

  git = {
    add    = "#a5e075",
    change = "#e5c07b",
    delete = "#ff616e",
  },

  -- ── Pretty Dark 扩展语义色（供 groups/base.lua 和 treesitter.lua 引用）
  type          = "#4ec9b0", -- 类型 / 类 / 接口
  property      = "#d19a66", -- 对象属性
  variable      = "#e06c75", -- 变量 / 参数
  constant      = "#e4bf7b", -- 常量 / 枚举 / const
  string_escape = "#56b6c2", -- 字符串转义
  operator      = "#c2c2c2", -- 运算符
  punctuation   = "#c2c2c2", -- 标点
}
return ret
