-- fff query 的纯文本处理：把 query 拆成「搜索词」与「筛选 token（glob / 路径 / 排除 / git:）」两组，
-- 以及把 explorer 选中的路径翻译成锚定到索引根的 glob token
-- 分类规则镜像 fff-query-parser（crates/fff-query-parser/src/{parser,config}.rs），
-- grep 与 files 两种模式的 glob 判定不同：grep 只认含 `/` 或 `{a,b}` 的 glob，避免 `arr[0]`、`foo?` 被吞掉
local Glob = require('vv-utils.glob')

local M = {}

local WILDCARD = '[%*%?%[{]'
local GIT_KEYS = { git = true, g = true, st = true, status = true }

---@param token string
---@return boolean
local function has_wildcard(token)
  return token:find(WILDCARD) ~= nil
end

--- 判断单个 token 是否会被 fff 解析为筛选约束（而非搜索文本）
---@param token string 不含空白的单个 token
---@param mode FffQueryMode
---@return boolean
function M.is_filter_token(token, mode)
  if token == '' or token:sub(1, 1) == '\\' then return false end

  local head = token:sub(1, 1)
  if head == '!' then
    local inner = token:sub(2)
    if inner == '' then return false end
    -- 取反文本（`!test`）要求 ≥3 字符且含字母数字，`!=` / `!==` 仍是搜索文本
    return M.is_filter_token(inner, mode) or (#inner >= 3 and inner:find('%w') ~= nil)
  end

  if head == '/' or (#token > 1 and token:sub(-1) == '/') then return true end

  if head == '*' then
    if token == '*' or token == '*.' then return false end
    if token:match('^%*%.[^%*%?%[{]+$') then return true end
  end

  if token:match('^type:') then return true end

  if mode == 'grep' then
    if not has_wildcard(token) then return false end
    if token:find('/', 1, true) then return true end
    local inner = token:match('{(.*)}')
    return inner ~= nil and inner:find(',', 1, true) ~= nil and inner:find('%a') ~= nil
  end

  if has_wildcard(token) then return true end
  local key = token:match('^(%w+):')
  return key ~= nil and GIT_KEYS[key] == true
end

--- 把 query 拆成搜索词与筛选 token，各自保持原有顺序
---@param query string
---@param mode FffQueryMode
---@return FffQueryParts
function M.split(query, mode)
  local parts = { text = {}, filters = {} }
  for token in query:gmatch('%S+') do
    local bucket = M.is_filter_token(token, mode) and parts.filters or parts.text
    bucket[#bucket + 1] = token
  end
  return parts
end

---@param source string
---@return boolean
local function is_native_key(source)
  local key = source:gsub('^!', ''):match('^(%w+):')
  return key ~= nil and (key == 'type' or GIT_KEYS[key] == true)
end

--- 把一组 glob pattern 合成单个 fff token：fff 多个 glob token 之间是 AND，合进一个 brace 才是 OR（与 rg 多个 --glob 一致）
--- vv-utils.glob 用前导 `/` 表示根锚定，fff glob 本身就以索引根锚定，去掉即可
---@param patterns string[]
---@param negated boolean
---@return string|nil
local function merge_patterns(patterns, negated)
  if #patterns == 0 then return nil end
  local list = vim.tbl_map(function(p) return (p:gsub('^/', '')) end, patterns)
  local token = #list == 1 and list[1] or ('{' .. table.concat(list, ',') .. '}')
  -- 不含 `/` 的单个 pattern 在 grep 模式不会被识别为 glob
  if #list == 1 and not token:find('/', 1, true) then token = './' .. token end
  return (negated and '!' or '') .. token
end

--- 把 <M-p> 输入编译成 fff 筛选 token，语义与 telescope 时代一致（vv-utils.glob，VS Code 风格）：
---   `lua/pack` → 任意深度的 lua/pack 本体与后代；`./lua/pack` → 锚定索引根；`.lua` → `*.lua`；`!x` 排除
---   顶层逗号或空白分隔多条规则，正向规则之间 OR，排除规则各自生效；`type:` / `git:` 为 fff 原生约束，原样保留
---@param input string
---@return string[]|nil tokens
---@return string|nil error
function M.compile_filters(input)
  local chunks, split_error = Glob.split(input)
  if not chunks then return nil, split_error end

  local tokens, include, exclude = {}, {}, {}
  for _, chunk in ipairs(chunks) do
    for source in chunk:gmatch('%S+') do
      if is_native_key(source) then
        tokens[#tokens + 1] = source
      else
        local compiled, compile_error = Glob.compile(source)
        if not compiled then return nil, compile_error end
        vim.list_extend(compiled.negated and exclude or include, compiled.patterns)
      end
    end
  end

  tokens[#tokens + 1] = merge_patterns(include, false)
  tokens[#tokens + 1] = merge_patterns(exclude, true)
  return tokens, nil
end

--- 用新的筛选输入替换 query 中全部筛选 token，搜索词保持原序
--- 结果带尾随空格：否则后续输入会粘在最后一个 glob 后面（`*.luafoo`）使整个 token 解析失败
---@param query string
---@param filter_input string 空串表示清除全部筛选
---@param mode FffQueryMode
---@return string|nil query
---@return string|nil error 筛选输入无法编译（如绝对路径、`../`）时返回错误，query 为 nil
function M.replace_filters(query, filter_input, mode)
  local filters, compile_error = M.compile_filters(filter_input)
  if not filters then return nil, compile_error end

  local tokens = M.split(query, mode).text
  vim.list_extend(tokens, filters)
  if #tokens == 0 then return '', nil end
  return table.concat(tokens, ' ') .. ' ', nil
end

---@param path string
---@return string
local function canonical(path)
  local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  abs = vim.uv.fs_realpath(abs) or abs
  return (abs:gsub('/+$', ''))
end

--- 把一组绝对路径翻译成 fff glob token（相对 root 锚定：目录 `./a/**`，文件 `./a/b.lu[a]`）
--- 文件名的一个字符包进 `[]`：纯路径不含通配符，grep 模式不会把它识别为 glob；`./` 前缀让顶层文件也含 `/`
--- 返回 nil 表示无法安全表达（在 root 之外、含空白或 glob 元字符），调用方应回退到 cwd 方案
---@param paths string[]
---@param root string 当前索引根（fff 每次 open 会切到 nvim cwd）
---@return string|nil
function M.scope_glob(paths, root)
  local base = canonical(root)
  local globs = {}

  for _, path in ipairs(paths) do
    local abs = canonical(path)
    if abs == base then return '' end

    local rel = vim.startswith(abs, base .. '/') and abs:sub(#base + 2) or nil
    if not rel or rel:find('[%s%*%?%[%]{},!\\]') then return nil end

    if vim.fn.isdirectory(abs) == 1 then
      globs[#globs + 1] = rel .. '/**'
    else
      -- 包最后一个 ASCII 字母数字而非末字节：末尾可能是多字节字符（中文文件名）
      local pos = rel:match('.*()%w')
      if not pos then return nil end
      globs[#globs + 1] = rel:sub(1, pos - 1) .. '[' .. rel:sub(pos, pos) .. ']' .. rel:sub(pos + 1)
    end
  end

  if #globs == 0 then return nil end
  if #globs == 1 then return './' .. globs[1] end
  return '{' .. table.concat(globs, ',') .. '}'
end

return M

---@alias FffQueryMode 'grep'|'files'

---@class FffQueryParts
---@field text string[] 搜索词 token
---@field filters string[] 筛选 token（glob / 路径段 / 取反 / type: / git:）
