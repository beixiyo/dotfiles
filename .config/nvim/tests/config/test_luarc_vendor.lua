-- 验证新增 vendor 在清单过期/缺失时仍有基础类型，并通过真实生成器补齐依赖
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])

-- Bun 的 import.meta.dir 会解析 macOS /var → /private/var，fixture 使用同一真实路径
local base = vim.fn.tempname()
vim.fn.mkdir(base, 'p')
base = assert(vim.uv.fs_realpath(base))
local config = base .. '/nvim'
local vendor = config .. '/vendors/vv-new.nvim'
local dependency = config .. '/vendors/vv-dependency.nvim'
local manifest_path = config .. '/.luarc-libraries.json'
local old_config_home = vim.env.XDG_CONFIG_HOME

local function write_json(path, value)
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

local function read_manifest()
  if vim.fn.filereadable(manifest_path) == 0 then return nil end
  return vim.json.decode(table.concat(vim.fn.readfile(manifest_path), '\n'))
end

local ok, err = pcall(function()
  vim.env.XDG_CONFIG_HOME = base
  H.eq(vim.fn.stdpath('config'), config, 'fixture 必须使用隔离配置目录')
  vim.fn.mkdir(vendor .. '/lua', 'p')
  vim.fn.mkdir(dependency .. '/lua', 'p')
  vim.fn.mkdir(config .. '/scripts', 'p')
  vim.fn.writefile({ "return require('vv-dependency')" }, vendor .. '/lua/vv-new.lua')
  vim.fn.writefile({ 'return {}' }, dependency .. '/lua/vv-dependency.lua')
  vim.fn.writefile(vim.fn.readfile(H.root .. '/scripts/gen-luarc.ts'), config .. '/scripts/gen-luarc.ts')

  local runtime = vim.env.VIMRUNTIME .. '/lua'
  local libraries = { '${3rd}/luv/library', runtime }
  write_json(config .. '/.luarc.json', { workspace = { library = libraries } })
  write_json(manifest_path, { base = libraries, projects = { [dependency] = {} } })

  local luarc = require('pack.luarc')
  H.eq(luarc.libraries_for(vendor), libraries,
    '清单遗漏新增 vendor 时，仍必须提供 Neovim 与 luv 类型库')
  H.eq(luarc.libraries_for(base), {}, '非 vendor 项目不能注入 Neovim 类型')
  H.eq(luarc.libraries_for(vendor .. '/lua'), {}, '不能把 vendor 子目录当成独立插件根')

  local function await_generation()
    H.capture_notify(function()
      luarc.setup()
      H.wait(function()
        local manifest = read_manifest()
        return manifest and manifest.projects[vendor]
          and vim.tbl_contains(manifest.projects[vendor], dependency)
      end, 10000, '启动检查必须用真实生成器补齐新增 vendor 及其 require 依赖')
    end)
    H.check(vim.tbl_contains(luarc.libraries_for(vendor), dependency),
      '更新后的清单必须向 vendor 注入真实依赖类型库')
  end

  await_generation()

  vim.fn.delete(manifest_path)
  H.eq(luarc.libraries_for(vendor), libraries,
    '清单缺失且异步生成尚未完成时，vendor 也必须有基础类型')
  await_generation()
end)

vim.env.XDG_CONFIG_HOME = old_config_home
vim.fn.delete(base, 'rf')
if not ok then error(err, 0) end
print('PASS: vendor 类型兜底、项目边界与自动更新')
