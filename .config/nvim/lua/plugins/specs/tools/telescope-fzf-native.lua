-- telescope 的 C sorter（fzf 算法 + FFI），装后模糊排序速度追平 fzf-lua
-- 两种构建方式：优先 make（简单、快）；WSL/Linux/macOS 基本都有
-- 否则走 sh -c cmake && cmake（table 形式绕过 pack 默认按空格切分的限制）
-- 纯 Windows 原生（cmd.exe）要手动改成：
--   build = { 'cmd', '/c', 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install' }
---@type PackSpec
return {
  desc = 'telescope 的 C sorter（fzf 算法 + FFI）',
  url = 'https://github.com/nvim-telescope/telescope-fzf-native.nvim',
  main = false,

  build = vim.fn.executable('make') == 1
    and 'make'
    or { 'sh', '-c', 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install' },
}
