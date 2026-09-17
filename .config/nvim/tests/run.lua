-- 一键测试入口：nvim -l tests/run.lua [过滤词]
-- 递归发现 tests/ 下所有 test_*.lua，每文件独立 nvim -l 子进程执行（失败隔离、环境干净）
-- 汇总结果，退出码非 0 = 有失败（可接 CI / &&）
local this = debug.getinfo(1, 'S').source:sub(2)
local tests_dir = vim.fn.fnamemodify(this, ':p:h')

local files = vim.fs.find(
  function(name) return name:match('^test_.*%.lua$') ~= nil end,
  { path = tests_dir, type = 'file', limit = -1 }
)
table.sort(files)

local pattern = arg and arg[1]
if pattern then
  files = vim.tbl_filter(function(f) return f:find(pattern, 1, true) end, files)
end

if #files == 0 then
  print('no test files found' .. (pattern and (': ' .. pattern) or ''))
  os.exit(1)
end

local function run_one(file)
  local out, code
  local jid = vim.fn.jobstart({ 'nvim', '-l', file }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, d) out = (out or '') .. table.concat(d, '\n') end,
    on_stderr = function(_, d) out = (out or '') .. table.concat(d, '\n') end,
    on_exit = function(_, c) code = c end,
  })
  vim.wait(120000, function() return code ~= nil end, 50)
  if code == nil then
    pcall(vim.fn.jobstop, jid)
    code = -1
    out = (out or '') .. '\n(timeout after 120s, killed)'
  end
  return code, out or ''
end

local failed = 0
local t0 = os.clock()
for _, file in ipairs(files) do
  local rel = vim.fs.relpath(tests_dir, file) or file
  local code, out = run_one(file)
  if code == 0 then
    print(('PASS  %s'):format(rel))
  else
    failed = failed + 1
    print(('FAIL  %s (exit %s)'):format(rel, code))
    for line in out:gmatch('[^\n]+') do
      print('      ' .. line)
    end
  end
end

print(('%d run, %d failed (%.1fs)'):format(#files, failed, os.clock() - t0))
os.exit(failed > 0 and 1 or 0)
