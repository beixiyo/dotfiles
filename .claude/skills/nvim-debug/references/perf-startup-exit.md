# 启动 / 退出耗时归因

验证环境：nvim 0.13.0-dev-1617（2026-10-22），macOS arm64。探针见 [probe-startup-exit.lua](probe-startup-exit.lua)

核心思路：先拿可重复的基线数字，再用下面的工具缩小范围，每一步都落文件，不要先猜插件。各节是工具箱而不是固定流程：症状已经指向某一处时（如只是退出慢），直接用对应的工具；工具不够用就自己写探针

文中带具体模块名的（pack、vv-mcp、tmux 等）是本配置的案例，换了配置不一定成立

## 1. 基线

```bash
for i in 1 2 3 4 5; do rm -f /tmp/st.log; nvim --headless --startuptime /tmp/st.log FILE +qa! >/dev/null 2>&1
  grep STARTED /tmp/st.log | awk '{printf "%s ", $1}'; done; echo
```

- 多跑几次（如 5 次），第一次常偏高（磁盘缓存、loader 建缓存），只比稳定值
- 按文件类型分开测（如空启动 / md / ts / lua，选用户实际常开的）：差值就是 FileType 链路（treesitter、LSP、ft 插件）的成本
- 用 `vim -es +qa` 做参照，判断差距量级
- `--startuptime` 末尾有空行，`tail -1` 拿不到结果，必须 `grep STARTED`
- 真实 TUI 的日志里有两条 `NVIM STARTED`，第一条约 3ms 的是 TUI 客户端进程，后一条才是服务端

## 2. 时间线：startuptime 的三种读法

```bash
# self 时间排序（require / sourcing 行第 3 列是 self）
awk '$3 ~ /^[0-9.]+:$/ {print $3, $0}' /tmp/st.log | sort -rn | head -30
# 找空白：相邻两行时间戳差 > 3ms 且中间没有任何 require，就是非 require 的纯计算
awk '{t=$1+0; if (t-prev>3) printf "GAP %.1fms before line %d: %s\n", t-prev, NR, $0; prev=t}' /tmp/st.log
# 阶段：opening buffers / VimEnter autocommands / UIEnter autocommands / first screen update
```

- `require('pack')` 这类入口的 self 很大，不代表它本身慢，往往是 searcher 或其中 eager 插件的 setup
- 空白段常见于 treesitter query 编译、同步外部进程、大文件解析，startuptime 不会单列出来，要用第 3 步定位
- 真实 TUI 的「空启动」可能并不空：auto-session 在 VimEnter 恢复会话会打开文件、分屏，要看 `sourcing .../sessions/*.vim` 这一行

## 3. 热点：jit.p

```bash
nvim --headless --cmd "lua require('jit.p').start('Fi1', '/tmp/flat.txt')" +"lua require('jit.p').stop()" +qa!
nvim --headless --cmd "lua require('jit.p').start('F3i1m2', '/tmp/stack.txt')" FILE +"lua require('jit.p').stop()" +qa!
```

- `_init_packages:16 < require` 占大头 = `vim._load_package` 在 rtp 里逐个找文件、重新解析源码，说明没开 `vim.loader`（`vim.loader.enabled` 可直接查）
- `query.lua:fn < _memoize.lua` = treesitter query 编译，用探针 `PERF_MODE=query` 拿每个 lang/name 的耗时
- `system:spawn` / `vim.fn.system` = 同步外部进程，回 startuptime 看是哪个模块（self 大但子 require 很少）

## 4. 单点计时：包函数、包 autocmd

- **包函数**：在 pack / 插件入口之前 `--cmd 'luafile probe.lua'`，替换 `mod.fn` 累计 hrtime。被包函数若会被别的模块再 monkey-patch（如 pack.stats 包 `loader.load`），自己的包裹要先装，否则计入的是外层
- **插件管理器自带的统计**可以先看一眼（本配置是 `_G.PackStats.plugins`，嵌套依赖是包含式计时，会重复计入）
- **包 autocmd**：`PERF_MODE=exit`，删除再按原顺序重建并计时。退出慢的元凶几乎都在 `VimLeavePre`
- **单个函数内部**：写 `-u NONE` 探针，手动 prepend rtp，逐步调用插件 setup 的每一步。本例定位到 vv-mcp `Registry.write` 6ms 是 `fsync`

## 5. 对照变量确认根因

只改一个变量重测基线，例如 `--cmd 'lua vim.loader.enable()'`，空启动 145→113ms，确认后再改配置。修完按第 1 步原样重跑，报改前改后两组数字

## 已知开销与结论（0.13-dev，macOS）

这是上次排查的结论，用来估算量级、帮助提出假设，不代替测量

| 现象 | 量级 | 结论 |
|---|---|---|
| 未开 `vim.loader`，60 条 rtp | 35–45ms | `init.lua` 首行 `vim.loader.enable()`。会话中途新建**顶层**模块（新的 `lua/<name>.lua`）require 不到，需重启或 `vim.loader.reset()`；改已有文件、已知目录新增文件都没问题（已探针验证） |
| `vim.fn.system` 调 tmux | 每次约 6ms | 用 `;` 命令链合并成一次；非退出路径改 `vim.system` 异步，并串行等前一个 job 保证写入顺序。**tmux 命令链里一条失败会中止后续**，可能失败的（如 `kill-session` 不存在的会话）放最后 |
| macOS `uv.fs_fsync` | 数 ms，磁盘忙时数十 ms | libuv 在 macOS 上走 `F_FULLSYNC`。临时 / 可重建文件用 rename 保证原子性即可，跳过 fsync |
| TS query 编译 | injections 44ms + highlights 38ms | 按 pattern 二分后成本是分散的（单条最多 5ms），是 tree-sitter 对大语法的固有分析开销，配置侧无单点可删 |
| LSP 优雅退出 | lua_ls 60–70ms，tsc 约 19ms，marksman 约 15ms | 不持久化状态的 server 可设 `exit_timeout = true` 直接终止；编辑都在 nvim 侧应用，rename 不受影响 |
| server 收到 exit 不关闭 | 等满 `exit_timeout` | `vim.lsp` exit handler 等的是 `client.rpc.is_closing()`；内置 Lua LSP（如 render-markdown）若不更新该状态就会等满超时 |

## 坑

- headless `+qa!` 在 VimEnter **之前**执行，挂在 VimEnter 的 dump 永远不触发；改用 VimLeavePre / VimLeave
- `client:is_stopped()` 在 `stop()` 后立即为 true，用它测出来都是 0ms；要等 `client.rpc.is_closing()`
- `client.rpc.pid` 为 nil，查 LSP 子进程用 `pgrep -P <nvim pid>`，退出后再 `kill -0` 确认回收
- 「等 LSP 就绪」只判断第一个 client 会漏掉其他 client（探针输出里会出现 `init=nil`），需要全部就绪时遍历判断
- **退出副作用会被迟到的回调撤销**：VimLeavePre 里删了文件，后续 handler 里的 `vim.wait` / `vim.fn.system` 会转动事件循环，LSP 停止触发的 `LspDetach` 排入的 `vim.schedule` 回调就在这时执行，把文件写回。验证退出清理要在进程结束**之后**查磁盘，不能在 handler 里查；修法是进入退出时置 `leaving` 标记
- 用 tmux 验证退出清理时，`tmux new-session ... "nvim"` 的 pane 会随 nvim 一起关闭，`show-options` 报错被 grep 吞掉，变成假的「已清理」。要用 `"nvim; sleep 30"` 让 pane 存活
