-- Mason 安装 + 各 language server 定义 + enable
--
-- 工作流：:Mason 手动安装 server → mason-lspconfig 检测到 → 自动 enable
--         → 打开对应 filetype 文件时自动 attach（懒启动）
-- 例外：TypeScript / Tailwind 不由 Mason 管，见下方说明

local M = {}

function M.setup()
  require('mason').setup({})
  require('mason-lspconfig').setup({
    ensure_installed = { 'dprint' },
    automatic_enable = {
      -- ts_ls 走的是 typescript-language-server（Node 包装器 + JS 版 tsserver），
      -- 已被下面的原生 Go 版取代，排除掉防止误装后被自动 enable
      exclude = { 'ts_ls' },
    },
  })

  -- ── TypeScript / Tailwind：脱离 Mason，由 mise 管理 ──────────────────────
  -- 两者都不再由 Mason 安装，因此 mason-lspconfig 的 automatic_enable 不会接管，
  -- 需要在本文件末尾手动 vim.lsp.enable()
  --
  -- 版本声明在 ~/.config/mise/config.toml，安装命令见该文件顶部注释
  -- ────────────────────────────────────────────────────────────────────────

  -- TypeScript：TS 7.0 正式版（Go 原生实现，比 JS 版 tsserver 快约 10x）
  --
  -- 二进制就是 typescript@7 的 tsc，故 client 名也叫 tsc（:checkhealth vim.lsp 里显示这个）
  --
  -- 上游 nvim-lspconfig 三个 TS 配置的实际指向（截至 2026-07 的 master）：
  --   ts_ls  → typescript-language-server，独立第三方项目，Node 包装 tsserver，非 Go
  --   vtsls  → 另一个 Node 包装器，同样是 JS 版
  --   tsgo   → microsoft/typescript-go，唯一的原生实现
  -- 三者都不叫 tsc：tsgo 是预览期的二进制名（@typescript/native-preview），
  -- 7.0 RC 起已正式改回 tsc 并发布到 typescript 包，但上游至今仍写死旧名和
  -- "experimental port" 的描述，所以这里自己定义配置名
  --
  -- 复用 tsgo 的默认值而非照抄：filetypes 与 root_dir（含 monorepo 探测 +
  -- Deno 项目排除，约 40 行）直接继承，只覆盖 cmd 和 settings
  local tsgo_defaults = vim.lsp.config.tsgo
  if type(tsgo_defaults) ~= 'table' or type(tsgo_defaults.root_dir) ~= 'function' then
    -- 上游若哪天删掉/改名 lsp/tsgo.lua，这里会静默丢掉 root_dir 导致工作区根判断失效
    vim.notify('[lsp] 未能继承 tsgo 默认配置，tsc 的 root_dir 可能不可用', vim.log.levels.WARN)
    tsgo_defaults = {}
  end

  -- 刻意只用全局 tsc、不优先找 node_modules/.bin/tsc：
  -- 项目本地若是 TS 5.x / 6.x，其 tsc 不认 --lsp，会直接启动失败
  -- 全局 TS7 的类型检查语义与 6.0 保持一致，跨项目通用
  --
  -- 设置上仅保留诊断/补全/导航偏好，格式化交由 dprint（~/.config/dprint/dprint.json）
  vim.lsp.config['tsc'] = vim.tbl_deep_extend('force', tsgo_defaults, {
    cmd = { 'tsc', '--lsp', '--stdio' },
    settings = {
      typescript = {
        preferences = {
          importModuleSpecifier = 'relative',
        },
      },
      javascript = {
        preferences = {
          importModuleSpecifier = 'relative',
        },
      },
    },
  })

  -- Tailwind：官方 language server 只有 Node 实现，没有 Rust/Go 替代品
  -- （唯一的 Rust 实现是个 1 star、2023 年起就停更的玩具）
  -- 上游内存问题至今未修（tailwindcss-intellisense#1553 仍 open），只能缓解：
  --
  --   1. 版本：Mason registry 把它钉在 0.14.29 且长期不更新，:MasonUpdate 也拿不到
  --      新版；0.16.0 修过递归 symlink 导致的 OOM，所以改由 mise 装
  --   2. 限堆：撞到上限就快速崩溃重启，而不是慢慢吃到 3–4GB 拖垮整机
  --   3. 补全端：该 server 每次返回约 9000–11000 条 item，务必配合
  --      blink.cmp >= 1.5.0（该版本专门优化了 tailwind 的 process_response）
  vim.lsp.config['tailwindcss'] = {
    cmd = { 'tailwindcss-language-server', '--stdio' },
    cmd_env = { NODE_OPTIONS = '--max-old-space-size=1024' },
    -- 显式指定入口可跳过全仓扫描探测（v3 填 tailwind.config.js，v4 填 CSS 入口）
    -- 路径因项目而异，故不在全局写死；需要时用 :h exrc 在项目内 .nvim.lua 覆盖：
    --   settings = { tailwindCSS = { experimental = { configFile = 'src/app.css' } } }
  }

  vim.lsp.enable({ 'tsc', 'tailwindcss' })
end

return M
