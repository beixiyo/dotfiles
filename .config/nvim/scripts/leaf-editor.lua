-- leaf 的外部编辑器适配：把快照源码行定位回创建预览的 Neovim buffer
-- 用法：nvim --headless -l leaf-editor.lua <server> <preview-id> <line|closed> [snapshot]
local server, id, action = arg[1], arg[2], arg[3]
local line = tonumber(action)
assert(server and id and (line or action == 'closed'), 'Missing leaf preview context')

-- sockconnect 既可能返回 0，也可能抛错；两种失败都不能触发 leaf 备用编辑器
local connected, channel = pcall(vim.fn.sockconnect, 'pipe', server, { rpc = true })
if not connected or channel <= 0 then
  io.stderr:write('Cannot connect to preview Neovim: ' .. tostring(channel) .. '\n')
  return
end

local ok, err = pcall(vim.rpcrequest, channel, 'nvim_exec_lua', [[
  local id, action, pid = ...
  local preview = require('tools.leaf-preview')
  if action == 'closed' then preview.remove(id)
  else preview.return_to_source(id, tonumber(action), pid) end
]], { id, action, vim.uv.os_getppid() })
vim.fn.chanclose(channel)
-- 非零退出会让 leaf 自动启动备用编辑器，误编辑临时快照；显式报告后正常结束
if not ok then io.stderr:write('leaf editor: ' .. tostring(err) .. '\n') end
