-- branches/delete.lua — 批量删除编排：多选分组 + 存在性校验
-- 保持纯/异步可直测，不碰 UI（confirm / 乐观移除 / refresh 留在 init.lua 闭包）
local M = {}

local parse_remote = require('plugins.specs.ui.telescope.git.branches.data').parse_remote

--- 多选 entries 分组：本地 / 按 remote 分组的远程 / is_head 跳过计数
---@param entries table[] telescope entry（含 value / is_head / is_remote）
---@return table { locals: string[], by_remote: table<string, string[]>, skipped: number }
function M.group(entries)
  local locals, by_remote, skipped = {}, {}, 0
  for _, e in ipairs(entries) do
    if e.is_head then
      skipped = skipped + 1
    elseif e.is_remote then
      local remote, branch = parse_remote(e.value)
      if remote then
        by_remote[remote] = by_remote[remote] or {}
        local list = by_remote[remote]
        list[#list + 1] = branch
      end
    else
      locals[#locals + 1] = e.value
    end
  end
  return { locals = locals, by_remote = by_remote, skipped = skipped }
end

--- 查询仍存在的分支（删除事后校验用；批量删除是部分成功语义，exit code 无法点名）
--- kind = 'local' → for-each-ref refs/heads；kind = 'remote' → ls-remote --heads <remote>
--- 在 cwd 的仓库内执行（harness fixture / 用户打开 picker 的仓库）
---@param kind string   'local' | 'remote'
---@param remote string?  kind=remote 时必填
---@param on_done function fun(names: string[]|nil)  仍存在的短名列表；nil = 查询本身失败
function M.existing(kind, remote, on_done)
  local args = kind == 'local'
    and { 'git', 'for-each-ref', '--format=%(refname:short)', 'refs/heads' }
    or  { 'git', 'ls-remote', '--heads', remote }

  local existing = {}
  vim.fn.jobstart(args, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      for _, line in ipairs(data or {}) do
        local name = kind == 'local' and line or line:match('^%x+\trefs/heads/(.+)$')
        if name and name ~= '' then existing[name] = true end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          on_done(nil)
          return
        end
        local names = {}
        for n in pairs(existing) do names[#names + 1] = n end
        table.sort(names)
        on_done(names)
      end)
    end,
  })
end

return M
