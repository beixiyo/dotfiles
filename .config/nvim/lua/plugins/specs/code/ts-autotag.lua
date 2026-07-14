-- nvim-ts-autotag：基于 tree-sitter 的 HTML/JSX/Vue 等标签自动闭合与同步重命名
-- 与 mini.pairs 互不重叠：mini 管单字符（()/[]/""），autotag 管 <tag></tag>
-- 依赖 treesitter parser；若打开新 ft（如 html/vue/svelte）请先确保对应 parser 已装
---@type PackSpec
return {
  desc = '标签自动闭合（HTML/JSX/Vue/Svelte）',
  url = 'https://github.com/windwp/nvim-ts-autotag',
  main = 'nvim-ts-autotag',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },

  -- 内置直接支持 + 走 alias 到 html/typescriptreact 的 ft 全列出来；
  -- 内置：html / xml / heex / typescriptreact / svelte / templ / glimmer
  -- 别名：astro / vue / markdown / php / blade / liquid / twig / eruby /
  --       htmlangular / htmldjango / javascriptreact / handlebars / rescript
  ft = {
    'html', 'xml', 'markdown',
    'typescriptreact', 'javascriptreact',
    'vue', 'svelte', 'astro',
    'php', 'blade', 'liquid', 'twig', 'eruby',
    'htmlangular', 'htmldjango',
    'heex', 'templ', 'glimmer', 'handlebars', 'rescript',
  },

  ---@type nvim-ts-autotag.Opts
  opts = {
    opts = {
      enable_close = true,
      enable_rename = true,
      enable_close_on_slash = true,
    },
  },
}
