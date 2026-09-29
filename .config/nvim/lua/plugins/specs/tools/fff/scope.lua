-- 以指定路径为范围启动 fff（供 vv-explorer 等调用方使用）
-- 优先把路径翻译成 query 里的 glob token：不切换索引根，关闭后普通搜索无需重建索引
-- 路径无法用 glob 安全表达时回退到 fff 的 cwd 选项（会触发一次重建索引，下次普通打开再切回 nvim cwd）
local Query = require('plugins.specs.tools.fff.query')

local M = {}

---@param paths string[]
---@param kind 'live_grep'|'find_files'
local function launch(paths, kind)
  if #paths == 0 then return end
  local ok, fff = pcall(require, 'fff')
  if not ok then
    vim.notify('fff 未启用', vim.log.levels.WARN)
    return
  end

  local root = vim.uv.cwd() or vim.fn.getcwd()
  local glob = Query.scope_glob(paths, root)
  local label = #paths == 1 and vim.fn.fnamemodify(paths[1], ':t') or (#paths .. ' paths')

  local opts = {
    title = (kind == 'live_grep' and 'Grep in ' or 'Files in ') .. label,
    renderer = kind == 'live_grep' and require('plugins.specs.tools.fff.grep_renderer') or nil,
  }
  if glob == nil then
    opts.cwd = vim.fn.isdirectory(paths[1]) == 1 and paths[1] or vim.fs.dirname(paths[1])
  elseif glob ~= '' then
    opts.query = glob .. ' '
  end
  fff[kind](opts)
end

--- 在给定路径（目录或文件，可多个）范围内 live grep
---@param paths string[] 绝对路径
function M.live_grep(paths) launch(paths, 'live_grep') end

--- 在给定路径范围内查找文件
---@param paths string[] 绝对路径
function M.find_files(paths) launch(paths, 'find_files') end

return M
