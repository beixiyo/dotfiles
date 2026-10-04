-- 将主题高亮导出为经典 Vim 配色；Vim 专用 UI 组也只从主题调色板取色
local M = {}

local mapping = {
  fg = "guifg",
  bg = "guibg",
  sp = "guisp",
}

--- @param colors ColorScheme
--- @param groups tokyonight.Highlights
--- @param opts tokyonight.Config
function M.generate(colors, groups, opts)
  opts.plugins = { all = false, auto = false, treesitter = false }
  local Groups = require("tokyonight.groups")
  for p, n in pairs(Groups.plugins) do
    if not p:find("nvim") then
      opts.plugins[n] = true
    end
  end
  groups = Groups.setup(colors, opts)
  local lines = {
    ([[
hi clear
let g:colors_name = "tokyonight-%s"
  ]]):format(colors._style),
  }

  -- 经典 Vim 的单文件状态栏与文件树没有插件来创建这些组
  -- 在导出层补齐，避免 .vimrc 再维护一份色值；不影响 Neovim 的运行时高亮
  groups = vim.tbl_extend("force", vim.deepcopy(groups), {
    SLModeN = "MiniStatuslineModeNormal",
    SLModeI = "MiniStatuslineModeInsert",
    SLModeV = "MiniStatuslineModeVisual",
    SLModeR = "MiniStatuslineModeReplace",
    SLModeC = "MiniStatuslineModeCommand",
    SLGit = { fg = colors.blue, bg = colors.bg },
    SLFile = { fg = colors.fg, bg = colors.bg },
    SLMod = { fg = colors.red, bg = colors.bg },
    SLFill = { fg = colors.comment, bg = colors.bg },
    SLFt = { fg = colors.cyan, bg = colors.bg },
    SLPos = { fg = colors.fg, bg = colors.bg_highlight },
    MiniExplorerIconDefault = "Normal",
    MiniExplorerIconBlue = "MiniIconsBlue",
    MiniExplorerIconCyan = { fg = colors.cyan },
    MiniExplorerIconGreen = "MiniIconsGreen",
    MiniExplorerIconYellow = "MiniIconsYellow",
    MiniExplorerIconOrange = "MiniIconsOrange",
    MiniExplorerIconRed = "MiniIconsRed",
    MiniExplorerIconPurple = "MiniIconsPurple",
    MiniExplorerIconMagenta = { fg = colors.magenta },
    MiniExplorerIconGrey = { fg = colors.comment },
    MiniExplorerIconGray = "MiniExplorerIconGrey",
    MiniExplorerIconWhite = "Normal",
  })
  for name in pairs(groups) do
    if name:sub(1, 1) == "@" then
      groups[name] = nil
    end
  end
  local names = vim.tbl_keys(groups)
  table.sort(names)

  local used = {}
  for _, name in ipairs(names) do
    local hl = groups[name]
    if type(hl) == "string" then
      hl = { link = hl }
    end

    if not hl.link then
      local props = {}

      -- fg/bg/sp
      for k, v in pairs(hl) do
        if mapping[k] then
          props[#props + 1] = ("%s=%s"):format(mapping[k], v)
        end
      end

      -- gui
      local gui = {}
      for _, attr in ipairs({
        "bold",
        "underline",
        "undercurl",
        "italic",
        "strikethrough",
        "underdouble",
        "underdotted",
        "underdashed",
        "inverse",
        "standout",
        "nocombine",
        "altfont",
      }) do
        if hl[attr] then
          gui[#gui + 1] = attr
        end
      end
      if #gui > 0 then
        props[#props + 1] = ("gui=%s"):format(table.concat(gui, ","))
      end

      if #props > 0 then
        -- hi clear 恢复内置默认值，不是清空所有属性：SpellCap / SpellBad
        -- 仍有 ctermbg，RGB 背景为 NONE 时即使 termguicolors 开启也会露出来
        -- 样式同步到全部通道；颜色只使用主题的 RGB 值，显式清掉终端色与缺省字段
        local attrs = #gui > 0 and table.concat(gui, ",") or "NONE"
        if #gui == 0 then
          props[#props + 1] = "gui=NONE"
        end
        props[#props + 1] = ("term=%s"):format(attrs)
        props[#props + 1] = ("cterm=%s"):format(attrs)
        props[#props + 1] = "ctermfg=NONE"
        props[#props + 1] = "ctermbg=NONE"
        for field, prop in pairs(mapping) do
          if not hl[field] then
            props[#props + 1] = prop .. "=NONE"
          end
        end
        table.sort(props)
        used[name] = true
        lines[#lines + 1] = ("hi %s %s"):format(name, table.concat(props, " "))
      else
        print("tokyonight: invalid highlight group: " .. name)
      end
    end
  end

  for _, name in ipairs(names) do
    local hl = groups[name]
    if type(hl) == "string" then
      hl = { link = hl }
    end

    if hl.link then
      if hl.link:sub(1, 1) ~= "@" and groups[hl.link] and used[hl.link] then
        lines[#lines + 1] = ("hi! link %s %s"):format(name, hl.link)
      end
    end
  end

  return table.concat(lines, "\n")
end

return M
