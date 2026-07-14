-- LuaSnip：VSCode 片段展开引擎（替代 vim.snippet 的默认实现）
--
-- 为什么需要：vim.snippet 不支持 ${var/regex/repl/flags} 变换以及 /pascalcase /upcase
-- 等字符串变换。rfc 等依赖 TM_FILEPATH + pascalcase 的 React 片段会失效
-- LuaSnip + jsregexp（C 扩展，提供 ECMA 正则）是目前 Neovim 生态里唯一的完整方案
--
-- 自动编译要求本地有 make + C 编译器。各平台最小依赖：
--
-- | 平台             | 依赖                    | 安装命令                                                             |
-- |------------------|-------------------------|----------------------------------------------------------------------|
-- | macOS            | Xcode Command Line      | xcode-select --install                                               |
-- | Debian / Ubuntu  | build-essential         | sudo apt install build-essential                                     |
-- | Arch / Manjaro   | base-devel              | sudo pacman -S base-devel                                            |
-- | Fedora / RHEL    | make + gcc              | sudo dnf install make gcc                                            |
-- | Alpine           | build-base              | apk add build-base                                                   |
-- | Windows (推荐)   | luarocks + Lua 5.1      | scoop install luarocks && luarocks --lua-version 5.1 install jsregexp|
-- | Windows (MSYS2)  | mingw-w64 + make        | pacman -S mingw-w64-ucrt-x86_64-gcc make                             |
-- | Windows (MSVC)   | VS Build Tools + nmake  | 在 Developer Command Prompt 里 `nmake install_jsregexp`              |
--

---@type PackSpec
return {
  desc = 'VSCode 片段引擎（带 jsregexp transform 支持）',
  url = { src = 'https://github.com/L3MON4D3/LuaSnip', version = vim.version.range('*') },
  main = 'luasnip',

  -- 与 blink.cmp 触发时机一致，priority 更高保证先加载
  event = { 'InsertEnter', 'CmdlineEnter', 'LspAttach' },
  priority = 50,

  -- 工具链缺失时 cond 返回 false：整个 spec 被 pack 排除，不下载、不加载 config
  -- 装完依赖后重启 nvim，cond 重新求值 → 自动下载 + 编译 jsregexp
  -- blink.cmp 侧用同样逻辑 fallback 到 vim.snippet（基础补全仍可用，仅 transform 失效）
  -- 工具链检测：作为 pack 的门闸（false → 不下载、不加载）并 notify 引导用户
  -- 与 blink.lua 里 snippets.preset 的判断逻辑严格对齐
  cond = function()
    if vim.fn.has('win32') == 0 and vim.fn.executable('make') == 1 then
      return true
    end

    local hint
    if vim.fn.has('win32') == 1 then
      hint = 'Windows: scoop install luarocks && luarocks --lua-version 5.1 install jsregexp'
    elseif vim.fn.has('mac') == 1 then
      hint = 'macOS: xcode-select --install'
    elseif vim.fn.executable('pacman') == 1 then
      hint = 'Arch: sudo pacman -S base-devel'
    elseif vim.fn.executable('apt') == 1 then
      hint = 'Debian/Ubuntu: sudo apt install build-essential'
    elseif vim.fn.executable('dnf') == 1 then
      hint = 'Fedora: sudo dnf install make gcc'
    elseif vim.fn.executable('apk') == 1 then
      hint = 'Alpine: apk add build-base'
    else
      hint = '安装 make + C 编译器后重启 nvim'
    end

    vim.notify_once(
      '[LuaSnip] 未检测到 C 编译工具链，已禁用（blink.cmp 自动 fallback 到 vim.snippet，transform 不可用）\n'
        .. hint
        .. '\n装完后重启 nvim 会自动下载并编译',
      vim.log.levels.WARN
    )
    return false
  end,

  -- 非 Ex 命令，走 shell 分支：cwd 为 LuaSnip 插件根
  -- cond 已守门，这里必然有 make 可用
  build = 'make install_jsregexp',

  config = function()
    require('luasnip').setup({
      update_events = { 'TextChanged', 'TextChangedI' },
      enable_autosnippets = false,
    })

    -- 加载 ~/.config/nvim/snippets：读 package.json + *.json + *.code-snippets
    require('luasnip.loaders.from_vscode').lazy_load({
      paths = { vim.fn.stdpath('config') .. '/snippets' },
    })
  end,
}
