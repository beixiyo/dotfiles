-- 使用 ripgrep 从项目配置中发现浏览器开发端口
local fs = require('vv-utils.fs')

local M = {}

local max_depth = 5
local env_pattern = [=[^[[:space:]]*(?:export[[:space:]]+)?(?:PORT|VITE_PORT|DEV_SERVER_PORT|FRONTEND_PORT|WEB_PORT)[[:space:]]*=[[:space:]]*['"]?([0-9]{2,5})]=]
local vite_pattern = [=[\bport[[:space:]]*:[[:space:]]*([0-9]{2,5})]=]

local excluded_globs = {
  '!**/.git/**',
  '!**/node_modules/**',
  '!**/dist/**',
  '!**/build/**',
  '!**/.next/**',
  '!**/.nx/**',
}

local env_file_rank = {
  ['.env.development.local'] = 1,
  ['.env.local'] = 2,
  ['.env.development'] = 3,
  ['.env'] = 4,
}

---@param root string
---@param globs string[]
---@param pattern string
---@return DapPortCandidate[]
local function scan(root, globs, pattern)
  if vim.fn.executable('rg') ~= 1 then return {} end

  local args = {
    'rg',
    '--hidden',
    '--no-ignore',
    '--with-filename',
    '--line-number',
    '--no-heading',
    '--color',
    'never',
    '--only-matching',
    '--replace',
    '$1',
    '--max-depth',
    tostring(max_depth),
  }

  for _, glob in ipairs(globs) do
    vim.list_extend(args, { '--glob', glob })
  end
  for _, glob in ipairs(excluded_globs) do
    vim.list_extend(args, { '--glob', glob })
  end

  vim.list_extend(args, { pattern, root })

  local result = vim.system(args, { text = true }):wait()
  if result.code ~= 0 and result.code ~= 1 then return {} end

  local candidates = {}
  for line in (result.stdout or ''):gmatch('[^\r\n]+') do
    local file, line_number, port = line:match('^(.-):(%d+):(%d+)$')
    port = tonumber(port)

    if file and port and port > 0 and port <= 65535 then
      local relative = file:sub(1, #root + 1) == root .. '/'
          and file:sub(#root + 2)
        or file
      local _, depth = relative:gsub('/', '/')

      candidates[#candidates + 1] = {
        file = fs.realpath(file),
        line = tonumber(line_number),
        port = port,
        depth = depth,
      }
    end
  end

  return candidates
end

---@param root string
---@return string
local function current_dir(root)
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file ~= '' then return fs.realpath(vim.fs.dirname(current_file)) end

  return fs.realpath(vim.uv.cwd() or root)
end

---@param from string
---@param to string
---@return integer
local function path_distance(from, to)
  local from_parts = vim.split(from, '/', { plain = true, trimempty = true })
  local to_parts = vim.split(to, '/', { plain = true, trimempty = true })
  local shared = 0

  while from_parts[shared + 1] and from_parts[shared + 1] == to_parts[shared + 1] do
    shared = shared + 1
  end

  return #from_parts + #to_parts - shared * 2
end

---@param candidates DapPortCandidate[]
---@param root string
---@param is_env? boolean
---@return DapPortCandidate?
local function first_candidate(candidates, root, is_env)
  local from = current_dir(root)

  table.sort(candidates, function(a, b)
    local a_distance = path_distance(from, vim.fs.dirname(a.file))
    local b_distance = path_distance(from, vim.fs.dirname(b.file))
    if a_distance ~= b_distance then return a_distance < b_distance end

    if is_env then
      local a_rank = env_file_rank[vim.fs.basename(a.file)] or 5
      local b_rank = env_file_rank[vim.fs.basename(b.file)] or 5
      if a_rank ~= b_rank then return a_rank < b_rank end
    end

    if a.depth ~= b.depth then return a.depth < b.depth end
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)

  return candidates[1]
end

---@param root string
---@return integer?
function M.detect(root)
  root = fs.realpath(root)

  local vite_candidate = first_candidate(scan(root, {
    'vite.config.js',
    'vite.config.ts',
    'vite.config.mjs',
    'vite.config.mts',
    'vite.config.cjs',
    'vite.config.cts',
  }, vite_pattern), root)
  if vite_candidate then return vite_candidate.port end

  local env_candidate = first_candidate(
    scan(root, { '.env', '.env.*' }, env_pattern),
    root,
    true
  )

  return env_candidate and env_candidate.port or nil
end

---@class DapPortCandidate
---@field file string
---@field line integer
---@field port integer
---@field depth integer

return M
