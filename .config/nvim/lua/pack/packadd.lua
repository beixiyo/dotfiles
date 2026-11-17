-- :packadd 的幂等封装
-- 原生 :packadd 对已挂载的目录仍会重新 source plugin/ 与 ftdetect/
-- 同一个依赖被多个 spec 声明时会被反复执行
local added = {}

---@param name string 插件目录名
---@return boolean ok
---@return string? err 失败时的错误信息（含 E919：目录不存在）
return function(name)
  if added[name] then return true end

  local ok, err = pcall(vim.cmd.packadd, name)
  -- 只记成功：失败（如尚未安装）的插件之后还能重试
  if ok then added[name] = true end
  return ok, not ok and tostring(err) or nil
end
