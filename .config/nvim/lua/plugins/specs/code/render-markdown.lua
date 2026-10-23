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

  ---@type render.md.UserConfig
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
      -- 直接走 Blink provider；内置 LSP 的 exit 未更新 closing 状态，会等满退出超时
      lsp = { enabled = false },
      blink = { enabled = true },
    },
    heading = {
      position = 'inline',
      backgrounds = {}, -- 不要标题底色（否则回落到插件默认的 Diff* 彩色底）
      icons = { '󰬺 ', '󰬻 ', '󰬼 ', '󰬽 ', '󰬾 ', '󰬿 ' },
    },
    code = {
      border = 'thin', -- 围栏行用细边框（代码块底色仍由 RenderMarkdownCode 提供）
      inline_pad = 1, -- 行内代码左右各补一格，底色连同空格一起包住
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
  -- 快速 undo/redo 时节点 range 越过被缩短的 buffer 会崩 "Index out of bounds"（上游 #649 至今未修）
  -- log.runtime 全仓库仅用于渲染调度这一处，pcall 包住即可：坏帧跳过、下次变更自愈（extmark 落点本就已 pcall）
  config = function(_, opts)
    require('render-markdown').setup(opts)

    local log = require('render-markdown.core.log')
    local orig_runtime = log.runtime
    log.runtime = function(name, cb)
      local inner = orig_runtime(name, cb)
      return function(...) pcall(inner, ...) end
    end

    -- 状态列宽度在首次渲染之后才定型（vv-statuscol 的 git / sign 列异步出现、行号位数增长），
    -- 而表格换行按「窗口宽度 - textoff」算列宽，textoff 变化不会触发 WinResized，
    -- 不补一次重渲表格右侧会多出 1 列被窗口分隔线盖住
    -- 只处理已 attach 且未被手动关闭的 buffer（同 core/manager.lua 处理 WinResized 的判断），
    -- 不会把关掉的渲染重新打开
    -- 重渲必须等过 debounce：插件对同一 buffer 在 debounce 窗口内的 update 直接丢弃、不补尾沿
    -- （lib/decorator.lua schedule），紧跟初次渲染发起的重渲会被吞掉
    local ok, statuscol = pcall(require, 'vv-statuscol')
    if ok and statuscol.on_width_change then
      local pending = {} ---@type table<integer, true>

      ---@param ctx { win: integer, buf: integer }
      ---@return boolean
      local function renderable(ctx)
        if not vim.api.nvim_win_is_valid(ctx.win) or vim.api.nvim_win_get_buf(ctx.win) ~= ctx.buf then
          return false
        end

        local m_ok, manager = pcall(require, 'render-markdown.core.manager')
        local s_ok, state = pcall(require, 'render-markdown.state')
        return m_ok and s_ok and manager.attached(ctx.buf) and state.get(ctx.buf).enabled
      end

      statuscol.on_width_change(function(ctx)
        if pending[ctx.buf] or not renderable(ctx) then return end

        pending[ctx.buf] = true
        local debounce = require('render-markdown.state').get(ctx.buf).debounce
        vim.defer_fn(function()
          pending[ctx.buf] = nil
          if not renderable(ctx) then return end

          require('render-markdown.core.ui').update(ctx.buf, ctx.win, 'WinResized', true)
        end, debounce + 20)
      end)
    end
  end,
}
