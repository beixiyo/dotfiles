-- 验证 Noice 连续确认框 workaround 只清理确认消息，并在私有 API 漂移时及时失败
vim.opt.runtimepath:prepend(vim.fn.stdpath('config') .. '/vendors/vv-icons.nvim')
require('pack.loader').load(require('plugins.specs.ui.noice'))

local state = require('noice.ui.state')

state.set('msg_show', '')
vim.api.nvim_exec_autocmds('CmdlineLeave', {})
assert(state.state.msg_show ~= nil, 'ordinary msg_show cache should be preserved')

state.set('msg_show', 'confirm')
vim.api.nvim_exec_autocmds('CmdlineLeave', {})
assert(state.state.msg_show == nil, 'confirm msg_show cache should be cleared')

print('noice confirm-scoped cleanup: PASS')
