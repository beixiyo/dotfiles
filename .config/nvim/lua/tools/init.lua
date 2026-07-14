-- 通用工具聚合（barrel）：统一 require('tools').xxx 取各子模块
-- 新增工具：在 lua/tools/ 下放 xxx.lua，并在此加一行 re-export + @field
-- 子模块无顶层副作用，eager require 安全；需要时再细化为惰性加载

---@class Tools
---@field palette tools.palette
---@field term tools.term
local M = {}

M.palette = require('tools.palette')
M.term = require('tools.term')

return M
