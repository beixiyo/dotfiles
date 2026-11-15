-- Vue 单文件组件
--
-- 官方 vue_ls 只管 <template> 与 <style>，<script> 里的 TypeScript 要靠 tsserver 加载 @vue/typescript-plugin
-- 原生 Go / Rust 版 TS server（tsc / tsrs）不支持 tsserver 插件
-- https://github.com/vuejs/language-tools/wiki/Neovim

local M = {}

function M.setup()
  -- 插件随 vue-language-server 一起安装，位置由 Mason 决定
  local plugin_path = vim.fn.stdpath('data') .. '/mason/packages/vue-language-server/node_modules/@vue/language-server'

  vim.lsp.config('vtsls', {
    filetypes = { 'vue' },
    settings = {
      vtsls = {
        tsserver = {
          globalPlugins = {
            {
              name = '@vue/typescript-plugin',
              location = plugin_path,
              languages = { 'vue' },
              configNamespace = 'typescript',
            },
          },
        },
      },
    },
  })
end

return M
