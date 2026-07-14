-- Markdown 渲染
---@type PackSpec
return {
  desc = 'Markdown 渲染预览',
  url = 'https://github.com/MeanderingProgrammer/render-markdown.nvim',
  main = 'render-markdown',
  dependencies = {
    'https://github.com/nvim-treesitter/nvim-treesitter',
    'https://github.com/nvim-tree/nvim-web-devicons',
  },
  ft = { 'markdown', 'AgenticChat' },

  ---@type render.md.Config
  opts = {
    enabled = true,
    file_types = { 'markdown', 'AgenticChat' },
    render_modes = { 'n', 'c', 'i', 't' },

    -- 仅光标所在行恢复原始 markdown，其余行保持渲染
    anti_conceal = {
      enabled = true,
      above = 0,
      below = 0,
    },
    completions = {
      coq = { enabled = false },
      lsp = { enabled = true },
      blink = { enabled = true },
    },
    heading = {
      position = 'inline',
      icons = { '󰬺 ', '󰬻 ', '󰬼 ', '󰬽 ', '󰬾 ', '󰬿 ' },
    },
    pipe_table = {
      cell = 'trimmed',
      padding = 0,
      min_width = 0,
    },

    -- 有序列表：直接显示原始序号，不在渲染期按 treesitter 位置重算
    -- （编号由 vv-markdown 在真实 buffer 里维护，单一数据源；否则缩进 < 标记宽度的嵌套
    --  会被 treesitter 当成扁平列表，把 `1.` 渲染成兄弟位置序号）
    bullet = {
      ordered_icons = function(ctx)
        return vim.trim(ctx.value)
      end,
    },

    -- Checkbox 自定义图标
    -- [ ] → unchecked  [x] → checked  [-] → todo（自定义状态，需 nvim >= 0.10）
    checkbox = {
      enabled = true,
      bullet = false,   -- 不显示 checkbox 前的列表符号
      right_pad = 1,

      unchecked = {
        icon = '󰄱 ',                        -- [ ]
        highlight = 'RenderMarkdownUnchecked',
      },
      checked = {
        icon = ' ',                        -- [x]
        highlight = 'RenderMarkdownChecked',
        scope_highlight = '@markup.strikethrough', -- 已完成项加删除线
      },

      -- 自定义中间状态，用 [-] 触发
      custom = {
        todo     = { raw = '[-]', rendered = '󰥔 ', highlight = 'RenderMarkdownTodo' },
        canceled = { raw = '[~]', rendered = '󰜺 ', highlight = 'RenderMarkdownError' },
      },
    },
  },

  -- 兜底 render-markdown 渲染崩溃：其渲染回调（core/ui.lua）里 get_node_text 无 pcall 守卫，
  -- 快速 undo/redo 时节点 range 越过被缩短的 buffer 会崩 "Index out of bounds"（上游 #649 至今未修）。
  -- log.runtime 全仓库仅用于渲染调度这一处，pcall 包住即可：坏帧跳过、下次变更自愈（extmark 落点本就已 pcall）。
  config = function(_, opts)
    require('render-markdown').setup(opts)

    local log = require('render-markdown.core.log')
    local orig_runtime = log.runtime
    log.runtime = function(name, cb)
      local inner = orig_runtime(name, cb)
      return function(...) pcall(inner, ...) end
    end
  end,
}
