local Util = require("tokyonight.util")

local M = {}

---@type tokyonight.HighlightsFn
function M.get(c, opts)
  -- stylua: ignore
  local ret = {
    ["@annotation"]                   = "PreProc",
    ["@attribute"]                    = "PreProc",
    ["@boolean"]                      = "Boolean",
    ["@character"]                    = "Character",
    ["@character.printf"]             = "SpecialChar",
    ["@character.special"]            = "SpecialChar",
    ["@comment"]                      = "Comment",
    ["@comment.error"]                = { fg = c.error },
    ["@comment.hint"]                 = { fg = c.hint },
    ["@comment.info"]                 = { fg = c.info },
    ["@comment.note"]                 = { fg = c.hint },
    ["@comment.todo"]                 = { fg = c.todo },
    ["@comment.warning"]              = { fg = c.warning },
    ["@constant"]                     = "Constant",
    ["@constant.builtin"]             = { fg = c.magenta, style = opts.styles.keywords },
    ["@constant.macro"]               = "Define",
    ["@constructor"]                  = { fg = c.property }, -- For constructor calls and definitions: `= { }` in Lua, and Java constructors.
    ["@constructor.tsx"]              = { fg = c.type },
    ["@diff.delta"]                   = "DiffChange",
    ["@diff.minus"]                   = "DiffDelete",
    ["@diff.plus"]                    = "DiffAdd",
    ["@function"]                     = "Function",
    ["@function.builtin"]             = "Function",
    ["@function.call"]                = "@function",
    ["@function.macro"]               = "Macro",
    ["@function.method"]              = "Function",
    ["@function.method.call"]         = "@function.method",
    ["@keyword"]                      = { fg = c.magenta, style = opts.styles.keywords }, -- For keywords that don't fall in previous categories.
    ["@keyword.conditional"]          = "@keyword",
    ["@keyword.coroutine"]            = "@keyword",
    ["@keyword.debug"]                = "Debug",
    ["@keyword.directive"]            = "PreProc",
    ["@keyword.directive.define"]     = "Define",
    ["@keyword.exception"]            = "@keyword",
    ["@keyword.function"]             = { fg = c.magenta, style = { italic = true } }, -- For keywords used to define a function.
    ["@keyword.import"]               = "@keyword",
    ["@keyword.operator"]             = "@keyword",
    ["@keyword.repeat"]               = "@keyword",
    ["@keyword.return"]               = "@keyword",
    ["@keyword.storage"]              = "@keyword",
    ["@label"]                        = { fg = c.blue }, -- For labels: `label:` in C and `:label:` in Lua.
    ["@markup"]                       = "@none",
    ["@markup.emphasis"]              = { fg = "#6f9bff", italic = true },
    ["@markup.environment"]           = "Macro",
    ["@markup.environment.name"]      = "Type",
    ["@markup.heading"]               = { fg = "#e06c75", bold = true },
    ["@markup.italic"]                = { fg = "#6f9bff", italic = true },
    ["@markup.link"]                  = { fg = "#61afef" },
    ["@markup.link.label"]            = { fg = "#61afef" },
    ["@markup.link.label.symbol"]     = "Identifier",
    ["@markup.link.url"]              = { fg = "#61afef", underline = true },
    ["@markup.list"]                  = { fg = c.punctuation }, -- For special punctutation that does not fall in the categories before.
    ["@markup.list.checked"]          = { fg = c.green },     -- For brackets and parens.
    ["@markup.list.markdown"]         = { fg = "#6f9bff", bold = true },
    ["@markup.list.unchecked"]        = { fg = c.blue },      -- For brackets and parens.
    ["@markup.math"]                  = "Special",
    ["@markup.raw"]                   = { fg = c.green },
    ["@markup.raw.markdown_inline"]   = { bg = c.bg_highlight, fg = c.teal },
    ["@markup.strikethrough"]         = { strikethrough = true },
    ["@markup.strong"]                = { fg = c.orange, bold = true },
    ["@markup.underline"]             = { underline = true },
    ["@module"]                       = "@keyword",
    ["@module.builtin"]               = { fg = c.variable }, -- Variable names that are defined by the languages, like `this` or `self`.
    ["@namespace.builtin"]            = "@variable.builtin",
    ["@none"]                         = {},
    ["@number"]                       = "Number",
    ["@number.float"]                 = "Number",
    ["@operator"]                     = { fg = c.operator },  -- For any operator: `+`, but also `->` and `*` in C.
    ["@property"]                     = { fg = c.property },
    ["@punctuation.bracket"]          = { fg = c.punctuation }, -- For brackets and parens.
    ["@punctuation.delimiter"]        = { fg = c.punctuation }, -- For delimiters ie: `.`
    ["@punctuation.special"]          = { fg = c.punctuation }, -- For special symbols (e.g. `{}` in string interpolation)
    ["@punctuation.special.markdown"] = { fg = "#6f9bff" },    -- For special symbols (e.g. `{}` in string interpolation)
    ["@string"]                       = "String",
    ["@string.documentation"]         = { fg = c.comment },
    ["@string.escape"]                = { fg = c.string_escape }, -- For escape characters within a string.
    ["@string.regexp"]                = { fg = c.variable },    -- For regexes.
    ["@tag"]                          = { fg = "#7d99db" },
    ["@tag.attribute"]                = "@property",
    ["@tag.builtin.tsx"]              = { fg = "#7d99db" },
    ["@tag.builtin.javascript"]       = { fg = "#7d99db" },
    ["@tag.delimiter"]                = "Delimiter",
    ["@tag.delimiter.tsx"]            = { fg = Util.blend_bg(c.blue, 0.7) },
    ["@tag.tsx"]                      = { fg = c.type },
    ["@tag.javascript"]               = { fg = c.type },
    ["@type"]                         = { fg = c.type },
    ["@type.builtin"]                 = { fg = c.type },
    ["@type.definition"]              = "@type",
    ["@type.qualifier"]               = "@keyword",
    ["@variable"]                     = { fg = c.variable, style = opts.styles.variables }, -- Any variable name that does not have another highlight.
    ["@variable.builtin"]             = { fg = c.magenta, style = opts.styles.keywords }, -- Variable names that are defined by the languages, like `this` or `self`.
    ["@variable.member"]              = { fg = c.property },                              -- For fields.
    ["@variable.parameter"]           = { fg = c.variable },                              -- For parameters of a function.
    ["@variable.parameter.builtin"]   = { fg = c.variable },                              -- For builtin parameters of a function, e.g. "..." or Smali's p[1-99]
  }

  local heading_color = "#e06c75"
  for i = 1, #c.rainbow do
    ret["@markup.heading." .. i .. ".markdown"] = { fg = heading_color, bold = true, bg = Util.blend_bg(heading_color, 0.1) }
  end
  return ret
end

return M
