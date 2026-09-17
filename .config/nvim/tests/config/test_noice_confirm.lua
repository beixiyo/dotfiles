-- 验证 Noice 连续确认框 workaround 只清理确认消息，并在私有 API 漂移时及时失败
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])

H.rtp('vendors/vv-icons.nvim')
require('pack.loader').load(require('plugins.specs.ui.noice'))

local state = require('noice.ui.state')

state.set('msg_show', '')
vim.api.nvim_exec_autocmds('CmdlineLeave', {})
H.check(state.state.msg_show ~= nil, 'ordinary msg_show cache should be preserved')

state.set('msg_show', 'confirm')
vim.api.nvim_exec_autocmds('CmdlineLeave', {})
H.check(state.state.msg_show == nil, 'confirm msg_show cache should be cleared')

print('PASS: noice confirm-scoped cleanup')
