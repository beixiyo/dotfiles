-- 覆盖 tokyonight.nvim 示例
-- 此方法会导致代码二次着色，首次渲染很慢，不推荐

local pd = require('tokyonight.colors.pretty_dark')

return {
  {
    'LazyVim/LazyVim',
    opts = {
      colorscheme = 'tokyonight',
    },
  },
  {
    'folke/tokyonight.nvim',
    lazy = false,
    priority = 1000,
    opts = {
      style = 'night',
      transparent = false,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        functions = {},
        variables = {},
        sidebars = 'dark',
        floats = 'dark',
      },
      on_colors = function(colors)
        -- 直接使用 pretty_dark 的颜色值
        -- 基础颜色
        colors.fg = pd.fg
        colors.fg_dark = pd.fg_dark
        colors.fg_gutter = pd.fg_gutter

        -- 语法高亮颜色
        colors.red = pd.red
        colors.green = pd.green
        colors.yellow = pd.yellow
        colors.blue = pd.blue
        colors.purple = pd.purple
        colors.cyan = pd.cyan
        colors.orange = pd.constant

        -- 特殊语法颜色
        colors.comment = pd.comment
        colors.blue0 = pd.blue  -- 函数颜色
        colors.blue1 = pd.blue1
        colors.blue2 = pd.blue
        colors.blue5 = pd.blue
        colors.blue6 = pd.blue1
        colors.blue7 = pd.blue
        colors.magenta = pd.magenta  -- 关键字颜色
        colors.magenta2 = pd.magenta2
        colors.teal = pd.string_escape
        colors.teal1 = pd.cyan
        colors.cyan = pd.type
        colors.cyan1 = pd.cyan
        colors.green1 = pd.green  -- 字符串颜色
        colors.green2 = pd.green2
        colors.yellow1 = pd.constant  -- 常量/数字颜色
        colors.yellow2 = pd.yellow
        colors.orange1 = pd.constant
        colors.orange2 = pd.yellow
      end,
      on_highlights = function(hl, c)
        -- 覆盖代码相关高亮组，保持其他 UI 高亮不变
        hl['@function'] = { fg = pd.blue }
        hl['@function.call'] = { fg = pd.blue }
        hl['@function.builtin'] = { fg = pd.blue }
        hl['@method'] = { fg = pd.blue }
        hl['@method.call'] = { fg = pd.blue }

        hl['@string'] = { fg = pd.green }
        hl['@string.escape'] = { fg = pd.string_escape }
        hl['@string.regex'] = { fg = pd.string_escape }
        hl['@string.special'] = { fg = pd.string_escape }

        hl['@keyword'] = { fg = pd.magenta, italic = true }
        hl['@keyword.function'] = { fg = pd.magenta, italic = true }
        hl['@keyword.operator'] = { fg = pd.magenta, italic = true }
        hl['@keyword.return'] = { fg = pd.magenta, italic = true }
        hl['@conditional'] = { fg = pd.magenta, italic = true }
        hl['@repeat'] = { fg = pd.magenta, italic = true }
        hl['@label'] = { fg = pd.magenta, italic = true }
        hl['@exception'] = { fg = pd.magenta, italic = true }

        hl['@constant'] = { fg = pd.constant }
        hl['@boolean'] = { fg = pd.constant }
        hl['@number'] = { fg = pd.constant }
        hl['@float'] = { fg = pd.constant }

        hl['@type'] = { fg = pd.type }
        hl['@type.builtin'] = { fg = pd.type }
        hl['@type.definition'] = { fg = pd.type }
        hl['@constructor'] = { fg = pd.type }
        hl['@property'] = { fg = pd.property }
        hl['@attribute'] = { fg = pd.property }
        hl['@field'] = { fg = pd.property }
        hl['@parameter'] = { fg = pd.variable }

        hl['@variable'] = { fg = pd.variable }
        hl['@variable.builtin'] = { fg = pd.red }

        hl['@operator'] = { fg = pd.operator }
        hl['@punctuation'] = { fg = pd.punctuation }
        hl['@punctuation.bracket'] = { fg = pd.punctuation }
        hl['@punctuation.delimiter'] = { fg = pd.punctuation }
        hl['@punctuation.special'] = { fg = pd.punctuation }

        hl['@comment'] = { fg = pd.comment, italic = true }
        hl['@comment.documentation'] = { fg = pd.comment }

        -- 导入关键字高亮
        hl['@keyword.import'] = { fg = pd.magenta, italic = true }
        hl['@keyword.export'] = { fg = pd.magenta, italic = true }
        hl['@module'] = { fg = pd.magenta }

        -- 标准 Vim 高亮组
        hl['Include'] = { fg = pd.magenta, italic = true }

        -- LSP 语义高亮
        hl['@lsp.type.variable'] = { fg = pd.variable }
        hl['@lsp.type.function'] = { fg = pd.blue }
        hl['@lsp.type.method'] = { fg = pd.blue }
        hl['@lsp.type.property'] = { fg = pd.property }
        hl['@lsp.type.parameter'] = { fg = pd.variable }
        hl['@lsp.type.type'] = { fg = pd.type }
        hl['@lsp.type.class'] = { fg = pd.type }
        hl['@lsp.type.interface'] = { fg = pd.type }
        hl['@lsp.type.enum'] = { fg = pd.constant }
        hl['@lsp.type.namespace'] = { fg = pd.magenta }
        hl['@lsp.type.keyword'] = { fg = pd.magenta, italic = true }
        hl['@lsp.type.string'] = { fg = pd.green }
        hl['@lsp.type.number'] = { fg = pd.constant }
        hl['@lsp.type.boolean'] = { fg = pd.constant }
        hl['@lsp.type.comment'] = { fg = pd.comment, italic = true }
      end,
    },
    config = function(_, opts)
      require('tokyonight').setup(opts)
    end,
  },
}
