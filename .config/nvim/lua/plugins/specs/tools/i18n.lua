-- vv-i18n.nvim — 通用 TS/TSX i18n 预览 / 跳转 / 同步改（对标 lokalise · i18n-ally）
-- 源码在 vendors/vv-i18n.nvim（走 pack.dev 本地重定向），可独立发布；包内默认中性
--
-- 本 spec 的 opts = 本机项目接入：多源 mono-repo。
-- - packages/comps：top-key 布局 + comps 前缀 + useT
-- - app / desktop renderer：react-i18next filename 布局
-- - tiptap-editor：flat 布局 + tiptap 固定前缀
-- 非匹配项目索引空 → 不激活、无噪声
---@type PackSpec
return {
  desc = 'i18n 预览/跳转/同步改（自研，tree-sitter）',
  url  = 'beixiyo/vv-i18n.nvim',
  main = 'vv-i18n',
  dependencies = { 'beixiyo/vv-utils.nvim', 'beixiyo/vv-icons.nvim' },

  -- 源码 / locale 文件打开即生效
  ft  = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  cmd = {
    'VVI18nInfo', 'VVI18nJump', 'VVI18nSetValue', 'VVI18nEdit', 'VVI18nKeys',
    'VVI18nMissing', 'VVI18nAddKey', 'VVI18nReload',
    'VVI18n', 'VVI18nEnable', 'VVI18nDisable', 'VVI18nToggle',
  },
  keys = function()
    local icon = '󰗊 '
    return {
      { '<leader>ik', '<cmd>VVI18nKeys<cr>',   desc = icon .. 'Browse keys' },
      { '<leader>ip', '<cmd>VVI18nInfo<cr>',   desc = icon .. 'Show translations' },
      { '<leader>id', '<cmd>VVI18nJump<cr>',   desc = icon .. 'Go to translation' },
      { '<leader>is', '<cmd>VVI18nEdit<cr>',   desc = icon .. 'Edit translations' },
      { '<leader>ia', '<cmd>VVI18nAddKey<cr>', desc = icon .. 'Add translation' },
      { '<leader>it', '<cmd>VVI18nToggle<cr>', desc = icon .. 'Toggle preview' },
      { '<leader>ir', '<cmd>VVI18nReload<cr>', desc = icon .. 'Reload translations' },
    }
  end,

  ---@type VVI18nConfig
  opts = {
    -- root 自动探测（pnpm-workspace.yaml > package.json > .git）
    sources = {
      {
        prefix    = 'comps',
        root      = 'packages/comps/src',
        discover  = { 'components/*/locales', 'i18n/common' },
        mount     = 'top-key',     -- 命名空间在文件内顶层 key
        namespace = 'two-level',   -- useT() → comps、useT('common') → comps.common
        lang      = '{lang}.ts',
        hooks     = { 'useT' },
      },
      {
        -- app 包：react-i18next，filename 布局（en-US/common.json，键在文件根）
        prefix    = '',
        root      = 'packages/app/src',
        discover  = { 'locales' },
        mount     = 'filename',         -- 命名空间 = 文件名（common）
        namespace = 'hook-arg',         -- useTranslation('common') → 前缀 common
        lang      = '{lang}/{ns}.json', -- en-US/common.json → lang=en-US, ns=common
        hooks     = { 'useTranslation' },
        t         = { 't' },
      },
      {
        -- desktop renderer：react-i18next，filename 布局（zh-CN/cards.json，键在文件根）
        prefix    = '',
        root      = 'frontend/electron/renderer',
        discover  = { 'locales' },
        mount     = 'filename',
        namespace = 'hook-arg',
        lang      = '{lang}/{ns}.json',
        hooks     = { 'useTranslation' },
        t         = { 't' },
      },
      {
        -- tiptap-editor：资源统一挂在 tiptap 根下，调用处写 t('comment.xxx')
        prefix    = 'tiptap',
        root      = 'tiptap-editor/packages/tiptap-api/src/i18n',
        discover  = { 'locales' },
        mount     = 'flat',
        namespace = function(ctx)
          if ctx.hook_name == 'useTiptapEditorT' then
            return 'tiptap'
          end

          if ctx.hook_name == 'useT' and ctx.hook_arg == 'tiptap' then
            return 'tiptap'
          end
        end,
        lang      = '{lang}.ts',
        hooks     = { 'useTiptapEditorT', 'useT' },
        t         = { 't' },
      },
    },
    display = { enable = true, preferred_langs = { 'zh-CN' } },
  },
}
