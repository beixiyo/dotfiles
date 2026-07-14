-- agentic.nvim  ACP (Agent Client Protocol) Chat
-- 需要本地已安装 ACP provider CLI
-- @see https://github.com/carlos-algms/agentic.nvim
--   pnpm add -g @agentclientprotocol/claude-agent-acp
--   pnpm add -g @zed-industries/codex-acp
-- 已安装的 provider 会沿用其自身的认证 / MCP / SKILLs，无需重复配置
--
-- ============================================================================
-- 【Buffer 内置键位速查】 聊天窗口里自动生效，本文件不需要重绑
-- ============================================================================
--
-- ▸ Chat widget（整个聊天区，含历史消息和上下文列表）
--     <S-Tab>            切 agent 模式（Plan / Accept edits / Bypass）
--     <localLeader>s     切 ACP provider（保留历史）
--     <localLeader>m     切模型（只在 widget 内可用，无全局 API）
--     <localLeader>p     粘贴剪贴板图片（需装 img-clip.nvim）
--     q                  关闭聊天窗
--     d                  在上下文条目 / 消息上按 = 删除该条
--
-- ▸ Prompt input（底部输入框，写 prompt 的地方）
--     <CR>  /  <C-s>     提交（n 模式）
--     <C-s>              提交（i / v 模式）
--     <Tab>              接受 @file / 斜杠命令补全（i 模式）
--     @                  触发文件拾取器（rg/fd/git-ls-files/Lua glob 兜底）
--     /                  触发斜杠命令补全（/new 永远有；其余由 provider 提供）
--     <C-v>              粘贴剪贴板图片（i 模式，需 img-clip.nvim）
--     拖拽图片入窗         所有支持 drag-and-drop 的终端都能用
--
-- ▸ Diff preview（agent 改文件时弹出的 diff 窗）
--     ]c  /  [c          下一个 / 上一个 hunk
--
-- ▸ Permission approval（权限审批弹窗）
--     1  2  3  4         allow once / allow always / reject once / reject always

local function a(name)
  return function(opts)
    require('agentic')[name](opts)
  end
end

---@type PackSpec
return {
  desc = 'ACP AI Chat（Claude/Gemini/Codex/...）',
  url = 'https://github.com/carlos-algms/agentic.nvim',
  main = 'agentic',
  dependencies = { 'beixiyo/vv-icons.nvim' },

  keys = function()
    local icons = require('vv-icons')
    local d = function(icon, text) return icon .. ' ' .. text end

    return {
    -- 主入口：terminal 风手感，i/t 模式也能切
      { '<C-A-b>', a('toggle'), mode = { 'n', 'v', 'i', 't' }, desc = d(icons.message, 'Toggle chat') },

    -- 会话
      { '<leader>at', a('toggle'),                    mode = { 'n', 'v' }, desc = d(icons.message, 'Toggle chat') },
      { '<leader>an', a('new_session'),               mode = { 'n' },      desc = d(icons.new_file, 'New session') },
      { '<leader>aN', a('new_session_with_provider'), mode = { 'n' },      desc = d(icons.new_file, 'New session with provider') },
      { '<leader>ar', a('restore_session'),           mode = { 'n' },      desc = d(icons.session, 'Restore session') },
      { '<leader>ap', a('switch_provider'),           mode = { 'n' },      desc = d(icons.config, 'Switch provider') },
      { '<leader>as', a('stop_generation'),           mode = { 'n' },      desc = d(icons.quit, 'Stop generation') },
      { '<leader>al', a('rotate_layout'),             mode = { 'n' },      desc = d(icons.window, 'Rotate layout') },

    -- 上下文（一键双模式：n=加当前文件，v=加选区）
      { '<leader>ac', a('add_selection_or_file_to_context'), mode = { 'n', 'v' }, desc = d(icons.copy, 'Add context') },
      { '<leader>ad', a('add_current_line_diagnostics'),     mode = { 'n' },      desc = d(icons.diagnostics, 'Add line diagnostics') },
      { '<leader>aD', a('add_buffer_diagnostics'),           mode = { 'n' },      desc = d(icons.diagnostics, 'Add buffer diagnostics') },
    }
  end,

  --- @type agentic.PartialUserConfig
  opts = function()
    local icons = require('vv-icons')
    local claude = icons.get('directory', '.claude')

    return {
      provider = 'claude-agent-acp',

      -- 窗口：紧凑一点
      windows = {
        position = 'right',
        width = '40%',
        input       = { height = 6 },
        code        = { max_height = 10 },
        files       = { max_height = 8 },
        diagnostics = { max_height = 8 },
        todos       = { display = true, max_height = 8 },
      },

      -- 标题栏：title · context，砍掉冗长 suffix help text
      --- @type agentic.UserConfig.Headers
      headers = {
        chat = function(parts)
          local ctx = parts.context and (' · ' .. parts.context) or ''
          return claude .. ' Agentic' .. ctx
        end,
        input       = { title = icons.code       .. ' Prompt',      suffix = '' },
        code        = { title = icons.code       .. ' Code',        suffix = '' },
        files       = { title = icons.find_file  .. ' Files',       suffix = '' },
        diagnostics = { title = icons.diagnostics .. ' Diagnostics', suffix = '' },
        todos       = { title = icons.marks      .. ' Todos',       suffix = '' },
      },

      -- 图标：统一 nerd font，干掉 emoji
      chat_icons = {
        user  = icons.ns.ui.cursor .. ' ',  -- 󰇀
        agent = claude .. ' ',              -- 󰚩
      },
      message_icons = {
        thinking = icons.ns.ui.lsp,   -- 󰘦
        finished = '',              -- nerd font check
        stopped  = '',              -- nerd font stop
        error    = icons.diagnostics_error,
      },
      status_icons = {
        pending     = icons.ns.ui.clock,  --  hourglass
        in_progress = icons.ns.ui.clock,
        completed   = '',               -- check
        failed      = icons.diagnostics_error,
      },
      diagnostic_icons = {
        error = icons.diagnostics_error,
        warn  = icons.diagnostics_warn,
        info  = icons.diagnostics_info,
        hint  = icons.diagnostics_hint,
      },
      spinner_chars = {
        generating = { '·', '✢', '✳', '∗', '✻', '✽' },
        thinking   = { '⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷' },
        searching  = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' },
      },

      diff_preview = {
        enabled = true,
        layout = 'split',
      },
    }
  end,

  config = function(_, opts)
    require('agentic').setup(opts)

    -- 让标题条贴合主题（tokyonight 没有 Agentic 组）
    vim.api.nvim_set_hl(0, 'AgenticTitle',    { link = 'Title' })
    vim.api.nvim_set_hl(0, 'AgenticThinking', { link = 'Comment' })
    vim.api.nvim_set_hl(0, 'AgenticSpinnerGenerating', { link = 'DiagnosticInfo', bold = true })
    vim.api.nvim_set_hl(0, 'AgenticSpinnerThinking',   { link = 'DiagnosticHint', bold = true })
    vim.api.nvim_set_hl(0, 'AgenticSpinnerSearching',  { link = 'DiagnosticWarn', bold = true })
    vim.api.nvim_set_hl(0, 'AgenticCodeBlockFence',    { link = 'Comment' })
  end,
}
