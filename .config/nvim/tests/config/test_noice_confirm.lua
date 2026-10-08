-- 验证 Noice 连续确认框 workaround 只清理确认消息，并在私有 API 漂移时及时失败
-- 经真实 pack.loader 加载 spec；隔离 pack 根只链接 env.sh 选择的依赖，不加载其他个人 package
local H = dofile('tests/helpers.lua')
local T, child = H.new_set({ 'VV_ICONS', 'VV_TEST_NOICE', 'VV_TEST_NUI', 'VV_TEST_NOTIFY' })

T['CmdlineLeave 只清理 confirm 的 msg_show 缓存'] = function()
  child.lua([[
    local pack_root = vim.env.VV_TEST_TMP .. '/packages'
    local opt = pack_root .. '/pack/test/opt'
    vim.fn.mkdir(opt, 'p')
    for name, key in pairs({
      ['noice.nvim'] = 'VV_TEST_NOICE', ['nui.nvim'] = 'VV_TEST_NUI',
      ['nvim-notify'] = 'VV_TEST_NOTIFY', ['vv-icons.nvim'] = 'VV_ICONS',
    }) do
      assert(vim.uv.fs_symlink(assert(vim.env[key]), opt .. '/' .. name))
    end
    vim.opt.packpath = pack_root
  ]])
  child.lua_func(function()
    require('pack.loader').load(require('plugins.specs.ui.noice'))
    local state = require('noice.ui.state')

    state.set('msg_show', '')
    vim.api.nvim_exec_autocmds('CmdlineLeave', {})
    check(state.state.msg_show ~= nil, '普通 msg_show 缓存必须保留')

    state.set('msg_show', 'confirm')
    vim.api.nvim_exec_autocmds('CmdlineLeave', {})
    check(state.state.msg_show == nil, 'confirm 的 msg_show 缓存必须清除')
  end)
end

return T
