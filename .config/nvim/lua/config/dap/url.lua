-- 浏览器调试 URL 的项目预填与持久记忆
local fs = require('vv-utils.fs')
local path = require('vv-utils.path')
local port = require('config.dap.port')

local M = {}

local default_port = 5173
local state_path = vim.fs.joinpath(vim.fn.stdpath('state'), 'dap', 'browser-urls.json')

local function project_root()
  local root = path.get_root()
  local workspace_root = vim.fs.root(root, {
    'pnpm-workspace.yaml',
    'nx.json',
    'turbo.json',
    '.git',
  })

  return fs.realpath(workspace_root or root)
end

---@param root string
---@return table
local function load_state(root)
  local state = fs.load_json(state_path)
  state.projects = type(state.projects) == 'table' and state.projects or {}
  state.projects[root] = type(state.projects[root]) == 'string' and state.projects[root] or nil
  return state
end

---@param root? string
---@return string
function M.default_url(root)
  root = fs.realpath(root or project_root())

  local remembered = load_state(root).projects[root]
  if remembered then return remembered end

  return ('http://localhost:%d'):format(port.detect(root) or default_port)
end

---@return string
function M.prompt()
  local root = project_root()
  local fallback = M.default_url(root)
  local entered = vim.trim(vim.fn.input('URL: ', fallback))
  local url = entered ~= '' and entered or fallback
  local state = load_state(root)

  state.projects[root] = url
  pcall(fs.save_json, state_path, state)

  return url
end

return M
