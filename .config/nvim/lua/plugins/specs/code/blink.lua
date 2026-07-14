-- blink.cmp 智能补全（替代 nvim-cmp）
-- 插入模式：LSP、路径、snippets、缓冲区；命令行 : / ? 补全（与 Noice 浮层配合）
-- LSP 配置中请使用：capabilities = require('blink.cmp').get_lsp_capabilities()
---@type PackSpec
return {
  desc = '补全与 LSP 增强',
  url = { src = 'https://github.com/saghen/blink.cmp', version = vim.version.range('*') },
  main = 'blink.cmp',

  -- ↓↓↓ blink-cmp-words：英文同义词/词典（约 45MB 离线词库），不要可整段注释 ↓↓↓
  dependencies = {
    'https://github.com/archie-judd/blink-cmp-words',
    'beixiyo/vv-icons.nvim',
  },
  -- ↑↑↑ blink-cmp-words ↑↑↑

  event = { 'InsertEnter', 'CmdlineEnter', 'LspAttach' },

  ---@return blink.cmp.Config
  opts = function()
    return {
      keymap = {
        preset = 'default',
        ['<C-Space>'] = { 'show' },
        ['<C-n>'] = { 'select_next', 'fallback' },
        ['<C-p>'] = { 'select_prev', 'fallback' },
        ['<Tab>'] = { 'select_and_accept', 'fallback' },
        ['<S-Tab>'] = { 'fallback' },
        ['<C-f>'] = { 'snippet_forward', 'fallback' },
        ['<C-b>'] = { 'snippet_backward', 'fallback' },
        ['<C-k>'] = { 'show_documentation', 'hide_documentation' },
        ['<C-e>'] = { 'scroll_documentation_down', 'fallback' },
        ['<C-y>'] = { 'scroll_documentation_up', 'fallback' },
      },

      appearance = {
        use_nvim_cmp_as_default = false,
        nerd_font_variant = 'mono',
        kind_icons = require('vv-icons').kinds,
      },

      enabled = function()
        return vim.bo.buftype ~= 'prompt' and vim.b.completion ~= false
      end,

      completion = {
        keyword = { range = 'full' },
        documentation = { auto_show = true, auto_show_delay_ms = 0 },
        list = { selection = { preselect = true, auto_insert = false } },
        ghost_text = { enabled = true },

        menu = {
          draw = {
            treesitter = { 'lsp' },
            columns = {
              { 'kind_icon' },
              { 'label', 'label_description', gap = 1 },
              { 'kind' },
              -- { 'source_name' },
            },
            components = {
              kind = {
                width = { fill = true },
                text = function(ctx) return ctx.kind end,
                highlight = function(ctx) return ctx.kind_hl end,
              },
              source_name = {
                width = { max = 30 },
                text = function(ctx) return '[' .. ctx.source_name .. ']' end,
                highlight = 'BlinkCmpSource',
              },
            },
          },
        },
      },

      -- 函数签名提示：输入左括号后浮窗显示当前参数（依赖 LSP textDocument/signatureHelp），和 LSP 文档作用重复了
      signature = { enabled = false },

      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
        providers = {
          -- LSP 首次响应可能超过 2s；异步返回，避免阻塞 snippets/path 的即时候选
          lsp = { score_offset = 4, async = true },
          path = { score_offset = 3 },
          snippets = { score_offset = 2 },
          buffer = { score_offset = 1 },

          -- ↓↓↓ blink-cmp-words 源定义，不要可整段注释 ↓↓↓
          thesaurus = {
            name = 'blink-cmp-words',
            module = 'blink-cmp-words.thesaurus',
            opts = { score_offset = 0, similarity_depth = 2 },
          },
          dictionary = {
            name = 'blink-cmp-words',
            module = 'blink-cmp-words.dictionary',
            opts = { score_offset = 0, dictionary_search_threshold = 3 },
          },
          -- ↑↑↑ blink-cmp-words 源定义 ↑↑↑
        },
        -- ↓↓↓ blink-cmp-words 按文件类型启用，不要可整段注释 ↓↓↓
        per_filetype = {
          text = { 'buffer', 'dictionary' },
          markdown = { 'lsp', 'path', 'snippets', 'buffer', 'thesaurus' },
          tex = { 'lsp', 'snippets', 'buffer', 'thesaurus', 'dictionary' },
          typst = { 'lsp', 'snippets', 'buffer', 'dictionary' },
        },
        -- ↑↑↑ blink-cmp-words per_filetype ↑↑↑
      },

      fuzzy = {
        -- Rust FFI 在 Linux 上 cmdline 补全时 SEGV: https://github.com/saghen/blink.cmp/issues/2155
        implementation = jit.os:lower() == 'linux' and 'lua' or 'prefer_rust_with_warning',
        prebuilt_binaries = {
          force_version = 'v*',
        },
      },

      cmdline = {
        enabled = true,
        keymap = {
          preset = 'cmdline',
          ['<Right>'] = false,
          ['<Left>'] = false,
          ['<C-n>'] = { 'select_next', 'fallback' },
          ['<C-p>'] = { 'select_prev', 'fallback' },
        },
        completion = {
          list = { selection = { preselect = false } },
          menu = { auto_show = true },
          ghost_text = { enabled = true },
        },
      },
    }
  end,

  -- 运行期探测 LuaSnip 是否真加载（同 events + priority 保证它先于 blink.cmp 完成 setup）
  -- LuaSnip 被 cond/user-picks 禁用时静默 fallback 到 vim.snippet
  --   LuaSnip 已加载 → 'luasnip'（支持 TM_FILEPATH/pascalcase 等 transform）
  --   否则 → 'default'（vim.snippet，无 transform，但基础补全可用）
  -- LuaSnip 的启用由它自己的 cond（C 工具链检测）和 user-picks 决定
  ---@param _ PackSpec
  ---@param opts blink.cmp.Config
  config = function(_, opts)
    local has_luasnip, luasnip = pcall(require, 'luasnip')
    opts.snippets = { preset = has_luasnip and 'luasnip' or 'default' }

    if has_luasnip then
      -- 不把光标前恰好可展开的文本误判为活动 snippet，否则精确匹配会隐藏候选
      opts.snippets.active = function(filter)
        if filter and filter.direction then
          return luasnip.locally_jumpable(filter.direction)
        end

        return luasnip.locally_jumpable(1) or luasnip.locally_jumpable(-1)
      end
    end

    require('blink.cmp').setup(opts)
  end,
}
