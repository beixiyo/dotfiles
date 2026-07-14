local Util = require("tokyonight.util")

local M = {}

---@type tokyonight.HighlightsFn
function M.get(c, opts)
  -- stylua: ignore
  return {
    ["@lsp.type.boolean"]                      = "@boolean",
    ["@lsp.type.constant"]                      = "@constant.builtin",
    ["@lsp.type.builtinType"]                  = { fg = c.type },
    ["@lsp.type.comment"]                      = "@comment",
    ["@lsp.type.decorator"]                    = "@attribute",
    ["@lsp.type.deriveHelper"]                 = "@attribute",
    ["@lsp.type.enum"]                         = "@type",
    ["@lsp.type.enumMember"]                   = "@constant",
    ["@lsp.type.escapeSequence"]               = "@string.escape",
    ["@lsp.type.formatSpecifier"]              = "@markup.list",
    ["@lsp.type.generic"]                      = "@variable",
    ["@lsp.type.interface"]                    = { fg = c.type },
    ["@lsp.type.keyword"]                      = "@keyword",
    ["@lsp.type.lifetime"]                     = "@keyword.storage",
    ["@lsp.type.namespace"]                    = "@module",
    ["@lsp.type.namespace.python"]             = "@variable",
    ["@lsp.type.number"]                       = "@number",
    ["@lsp.type.operator"]                     = "@operator",
    ["@lsp.type.parameter"]                    = "@variable.parameter",
    ["@lsp.type.property"]                     = "@property",
    ["@lsp.type.selfKeyword"]                  = "@variable.builtin",
    ["@lsp.type.selfTypeKeyword"]              = "@variable.builtin",
    ["@lsp.type.string"]                       = "@string",
    ["@lsp.type.typeAlias"]                    = "@type.definition",
    ["@lsp.type.unresolvedReference"]          = { undercurl = true, sp = c.error },
    ["@lsp.type.variable"]                     = {}, -- use treesitter styles for regular variables
    ["@lsp.typemod.class.defaultLibrary"]      = { fg = c.type },
    ["@lsp.typemod.enum.defaultLibrary"]       = { fg = c.type },
    ["@lsp.typemod.enumMember.defaultLibrary"] = "@constant.builtin",
    ["@lsp.typemod.function.defaultLibrary"]   = "@function.builtin",
    ["@lsp.typemod.keyword.async"]             = "@keyword.coroutine",
    ["@lsp.typemod.keyword.injected"]          = "@keyword",
    ["@lsp.typemod.macro.defaultLibrary"]      = "@function.builtin",
    ["@lsp.typemod.method.defaultLibrary"]     = "@function.builtin",
    ["@lsp.typemod.operator.injected"]         = "@operator",
    ["@lsp.typemod.string.injected"]           = "@string",
    ["@lsp.typemod.struct.defaultLibrary"]     = { fg = c.type },
    ["@lsp.typemod.type.defaultLibrary"]       = { fg = c.type },
    ["@lsp.typemod.typeAlias.defaultLibrary"]  = { fg = c.type },
    ["@lsp.typemod.variable.callable"]         = "@function",
    ["@lsp.typemod.variable.defaultLibrary"]   = { fg = c.constant, style = opts.styles.keywords },
    ["@lsp.typemod.variable.injected"]         = "@variable",
    ["@lsp.typemod.variable.readonly"]         = "@constant", -- const 声明的变量
    ["@lsp.typemod.variable.static"]           = "@constant",

  }
end

return M
