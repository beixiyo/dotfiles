-- nvim-treesitter-textobjects：结构化跳转
--   ]f/[f 函数调用、]v/[v 变量声明、]s/[s 字符串、]t/[t 标签、]p/[p 属性
-- 🔗 https://github.com/nvim-treesitter/nvim-treesitter-textobjects
---@type PackSpec
return {
  desc = '结构化文本对象与跳转',
  url = 'https://github.com/nvim-treesitter/nvim-treesitter-textobjects',
  main = 'nvim-treesitter-textobjects',
  dependencies = { 'nvim-treesitter/nvim-treesitter' },

  keys = {
    { ']f', function() require('nvim-treesitter-textobjects.move').goto_next_start('@call.outer') end, mode = { 'n', 'x', 'o' },       desc = 'Next call' },
    { '[f', function() require('nvim-treesitter-textobjects.move').goto_previous_start('@call.outer') end, mode = { 'n', 'x', 'o' },  desc = 'Previous call' },
    { ']F', function() require('nvim-treesitter-textobjects.move').goto_next_end('@call.outer') end, mode = { 'n', 'x', 'o' },         desc = 'Next call end' },
    { '[F', function() require('nvim-treesitter-textobjects.move').goto_previous_end('@call.outer') end, mode = { 'n', 'x', 'o' },    desc = 'Previous call end' },
    { ']v', function() require('nvim-treesitter-textobjects.move').goto_next_start('@assignment.lhs') end, mode = { 'n', 'x', 'o' },   desc = 'Next variable' },
    { '[v', function() require('nvim-treesitter-textobjects.move').goto_previous_start('@assignment.lhs') end, mode = { 'n', 'x', 'o' }, desc = 'Previous variable' },
    { ']V', function() require('nvim-treesitter-textobjects.move').goto_next_end('@assignment.lhs') end, mode = { 'n', 'x', 'o' },     desc = 'Next variable end' },
    { '[V', function() require('nvim-treesitter-textobjects.move').goto_previous_end('@assignment.lhs') end, mode = { 'n', 'x', 'o' }, desc = 'Previous variable end' },
    { ']s', function() require('nvim-treesitter-textobjects.move').goto_next_start('@string.outer', 'strings') end, mode = { 'n', 'x', 'o' }, desc = 'Next string' },
    { '[s', function() require('nvim-treesitter-textobjects.move').goto_previous_start('@string.outer', 'strings') end, mode = { 'n', 'x', 'o' }, desc = 'Previous string' },
    { ']S', function() require('nvim-treesitter-textobjects.move').goto_next_end('@string.outer', 'strings') end, mode = { 'n', 'x', 'o' },    desc = 'Next string end' },
    { '[S', function() require('nvim-treesitter-textobjects.move').goto_previous_end('@string.outer', 'strings') end, mode = { 'n', 'x', 'o' }, desc = 'Previous string end' },
    { ']t', function() require('nvim-treesitter-textobjects.move').goto_next_start('@tag.outer') end, mode = { 'n', 'x', 'o' },              desc = 'Next tag' },
    { '[t', function() require('nvim-treesitter-textobjects.move').goto_previous_start('@tag.outer') end, mode = { 'n', 'x', 'o' },         desc = 'Previous tag' },
    { ']T', function() require('nvim-treesitter-textobjects.move').goto_next_end('@tag.outer') end, mode = { 'n', 'x', 'o' },                desc = 'Next tag end' },
    { '[T', function() require('nvim-treesitter-textobjects.move').goto_previous_end('@tag.outer') end, mode = { 'n', 'x', 'o' },           desc = 'Previous tag end' },
    { ']p', function() require('nvim-treesitter-textobjects.move').goto_next_start('@property.outer') end, mode = { 'n', 'x', 'o' },        desc = 'Next property' },
    { '[p', function() require('nvim-treesitter-textobjects.move').goto_previous_start('@property.outer') end, mode = { 'n', 'x', 'o' },   desc = 'Previous property' },
    { ']P', function() require('nvim-treesitter-textobjects.move').goto_next_end('@property.outer') end, mode = { 'n', 'x', 'o' },          desc = 'Next property end' },
    { '[P', function() require('nvim-treesitter-textobjects.move').goto_previous_end('@property.outer') end, mode = { 'n', 'x', 'o' },     desc = 'Previous property end' },
  },

  opts = {
    move = {
      set_jumps = true,
    },
  },

  config = function(_, opts)
    require('nvim-treesitter-textobjects').setup(opts)

    -- 注册 @property.outer 自定义 capture
    -- 用于 ]p/[p 属性跳转（对象键值对 / JSX 属性 / CSS 声明 / YAML 键值对 / JSON 键值对 / TOML 键值对）
    local function register_lang_property(lang, pattern)
      vim.treesitter.query.set(lang, 'textobjects', table.concat({
        '; extends',
        pattern,
      }, '\n'))
    end

    register_lang_property('javascript', '(pair) @property.outer')
    register_lang_property('typescript', '(pair) @property.outer')
    register_lang_property('tsx', '[(pair) (jsx_attribute)] @property.outer')
    register_lang_property('json', '(pair) @property.outer')
    register_lang_property('jsonc', '(pair) @property.outer')
    register_lang_property('toml', '(pair) @property.outer')
    register_lang_property('yaml', '[(block_mapping_pair) (flow_pair)] @property.outer')
    register_lang_property('css', '(declaration) @property.outer')
    register_lang_property('scss', '(declaration) @property.outer')
    register_lang_property('less', '(declaration) @property.outer')

    local modes = { 'n', 'x', 'o' }
    local ts_repeat = require('nvim-treesitter-textobjects.repeatable_move')
    vim.keymap.set(modes, ';', ts_repeat.repeat_last_move)
    vim.keymap.set(modes, ',', ts_repeat.repeat_last_move_opposite)
  end,
}
