---@type PackSpec
return {
  desc = '增强增减与 Toggle',
  url = 'monaqa/dial.nvim',
  main = false,

  ---@return PackKeySpec[]
  keys = function()
    return {
      { '<C-a>', function() return require('dial.map').inc_normal() end, expr = true, desc = 'Increment' },
      { '<C-x>', function() return require('dial.map').dec_normal() end, expr = true, desc = 'Decrement' },
      { '<C-a>', function() return require('dial.map').inc_visual() end, mode = 'v', expr = true, desc = 'Increment' },
      { '<C-x>', function() return require('dial.map').dec_visual() end, mode = 'v', expr = true, desc = 'Decrement' },
      { 'g<C-a>', function() return require('dial.map').inc_gvisual() end, mode = 'v', expr = true, desc = 'Increment sequence' },
      { 'g<C-x>', function() return require('dial.map').dec_gvisual() end, mode = 'v', expr = true, desc = 'Decrement sequence' },
    }
  end,

  ---@param _ PackSpec
  config = function(_)
    local augend = require('dial.augend')

    ---@type Augend[]
    local default_augends = {
      augend.integer.alias.decimal_int,
      augend.integer.alias.hex,
      augend.integer.alias.octal,
      augend.integer.alias.binary,

      augend.constant.alias.bool,
      augend.constant.new({ elements = { 'yes', 'no' }, word = true, cyclic = true }),
      augend.constant.new({ elements = { 'on', 'off' }, word = true, cyclic = true }),
      augend.constant.new({ elements = { 'enable', 'disable' }, word = true, cyclic = true }),
      augend.constant.new({ elements = { 'enabled', 'disabled' }, word = true, cyclic = true }),

      augend.constant.new({ elements = { 'AND', 'OR' }, word = true, cyclic = true }),
      augend.constant.new({ elements = { '&&', '||' }, word = false, cyclic = true }),
      augend.constant.new({ elements = { '===', '!==' }, word = false, cyclic = true }),
      augend.constant.new({ elements = { '==', '!=' }, word = false, cyclic = true }),
      augend.constant.new({ elements = { '>=', '<=' }, word = false, cyclic = true }),
      augend.constant.new({ elements = { '>', '<' }, word = false, cyclic = true }),

      augend.constant.new({ elements = { 'let', 'const' }, word = true, cyclic = true }),
      augend.constant.new({ elements = { 'public', 'private', 'protected' }, word = true, cyclic = true }),

      augend.date.alias['%Y-%m-%d'],
      augend.date.alias['%Y/%m/%d'],
      augend.date.alias['%m/%d'],
      augend.semver.alias.semver,
    }

    require('dial.config').augends:register_group({ default = default_augends })
  end,
}
