# AGENTS.md — Neovim 配置

## 入口与文档

- Neovim 0.12+，基于原生 `vim.pack`；`vim.loader.enable()` 保持为 `init.lua` 首个执行语句
- 插件声明在 `lua/plugins/specs/{code,tools,ui}/`；加载、spec 字段与默认值见 [pack README](lua/pack/README.md)
- `vendors/vv-*.nvim` 通常是独立 Git 仓库；修改前读 [vendors 约定](vendors/AGENTS.md) 和目标仓文档。插件怎么写（全局状态、跨插件约定、错误路径、生命周期）以它为准，本文只记配置层的规则和 Neovim 行为陷阱
- 共享能力先查 [vv-utils README](vendors/vv-utils.nvim/README.zh-CN.md)，不要在各插件重复实现
- 特殊边界：[空 buffer 清理](vendors/vv-utils.nvim/lua/vv-utils/bufdelete/README.md)、[Telescope ANSI / terminal preview](lua/plugins/specs/ui/telescope/README.md)

## 交互与窗口

- 普通 j/k 单步立即响应；快速连续移动才合并昂贵预览，不给每一步统一加尾沿防抖
- 未确认预览关闭时回到原 buffer 与视口；确认打开或编辑后保留。仅悬停不加入固定标签
- 异步初始定位只在用户尚未导航时执行；后台刷新不抢焦点、不把光标或滚动位置拉回旧状态
- 全局快捷键放 spec `keys`。真实文件与插件 scratch 分开绑定，优先不接管已有键位，不为此代理任意旧映射
- buffer-local 映射影响该 buffer 的所有窗口；不能用它假定 window-local 行为
- 临时窗口选项显式写 `vim.wo[win][0].opt` 或 `{ win = win, scope = 'local' }`；逐项核验继承，local 仍可能被同 buffer split 复制
- 还原选项须匹配原窗口／buffer，且当前仍为自己所设的值；不要把 A 的基线写给 B，或覆盖后来修改
- 窗口局部选项有三层：`vim.o` 只写全局值和当前窗口，其余窗口保留各自的值；每个窗口还带一份自己的默认值（`{ win = win, scope = 'global' }`），换 buffer 时从它重置；`style = 'minimal'` 属于窗口配置，换 buffer 会重新套用，还原窗口须先 `nvim_win_set_config(win, { style = '' })`
- `:bdelete`／`nvim_buf_delete` 会关掉显示该 buffer 的窗口，只要还有别的非浮动窗口。用真实 split 做装饰或面板的插件必须能承受自己成为最后一个窗口；删除用户 buffer 走 [vv-utils.bufdelete](vendors/vv-utils.nvim/lua/vv-utils/bufdelete/README.md)，先换 buffer 再删
- 映射里把按键原样交还时用 `nvim_feedkeys(keys, 'in', false)` 插到队列最前；追加到末尾会排在用户已输入的后续按键之后（`qa` 变成先 `a` 后 `q`）
- 关闭别的插件的浮窗走它自己的关闭入口；一个组件常由多个窗口组成（内容＋不可聚焦的边框），直接 `nvim_win_close` 其中一个会留下残影

## Loading 与视觉

- 用 `require('tools.palette')`；独立插件提供高亮组／配置入口，不依赖本机 palette
- 可感知等待且界面无反馈时用 [vv-utils.loading](vendors/vv-utils.nvim/lua/vv-utils/loading/README.md)；短任务设 `delay_ms` 防闪烁，不自建动画 timer
- 加载动画优先放在名称旁，或替换原图标并保持宽度不变；不要放在可能被窄窗口截掉的长行末尾
- 行内用 `mark`，浮窗标题／页脚用 `win_text`，自绘文本用 `ticker`，同位置并发用 `slot`；帧与文案分别用 `VVLoading`／`VVLoadingLabel`
- Telescope 用结果窗标题或 preview 骨架，首个有效输出替换占位；必须同步且无其它 UI 才用 `blocking`，它不提供持续动画
- Loading 到结果实际应用后才结束；失败／取消也释放。旧请求不得停掉新请求的反馈，同一窗口槽位不叠多个 `win_text`，`ticker` 由 owner 显式停止

## 性能机制

API 与边界见 [async](vendors/vv-utils.nvim/lua/vv-utils/async/README.md)、[timer](vendors/vv-utils.nvim/lua/vv-utils/timer/README.md)

| 场景 | 项目选择与易错点 |
|---|---|
| 同批重复刷新 | `async.coalesce`；多次 `vim.schedule` 本身不合并，同步状态维护不能一起推迟 |
| 批量解析／扫描 | `async.batch` 时间预算分片；禁止 `vim.schedule` 自递归，它可能同批排空而不出让 |
| 独立重计算 | `async.worker_task`；编辑器状态与 UI 留主线程，取消不保证物理终止 |
| 高频预览 | 明确首尾沿和末次交付；`timer.throttle` 默认丢弃窗口内调用，需要末次结果时启用 trailing |
| 索引／共享数据 | 首次消费时构建，同轮多视图共享；只取 root 等元数据时不要深拷贝整个索引 |

- 热路径避免 `vim.fn.system`／`vim.system():wait()`；优先异步 IO，不把延迟到首次使用当成消除成本
- 关闭／重开时除取消 timer，还须拦截已排队的旧回调；核对请求代际与窗口／buffer 身份
- `VimLeavePre` 后仍可能处理排队事件；退出标记必须阻止刷新写回。LSP 退出策略见 `lua/plugins/specs/code/lsp/lifecycle.lua`
- 不把扫描失败／取消当作空结果来判断 unused；部分索引不能作为删除依据
- 用户内容和恢复元数据不能按缓存降低持久化保证；同目录 rename 原子性不等于断电持久
- 懒加载调整须检查 plugin/config、ftdetect、after/plugin、首次事件及 VSCode／build 路径；不机械替换 `packadd`
- 远程 lazy 插件触发前不在 rtp 上，require／未定义命令／`:help` 由 `pack.ondemand` 兜底，边界见 pack README

## 验证入口

- 根配置或对应 vendor 中运行 `sh tests/run.sh [过滤词]`；测试隔离与依赖声明见 [共享测试规范](vendors/vv-utils.nvim/dev/test/README.md)
- spec／pack 改动运行 `:lua require('pack.smoke').run()`；它只验证加载与结构，不验证交互
- 窗口／键位改动重点复验同 buffer 多窗、关闭重开、后来 owner；预览检查确认／取消与过期回调；Loading 检查窄窗可见性及失败收尾
- 会话类交互按结束路径逐条验：确认、取消、在别处（分屏／另一窗口）打开、目标被删除、快速连按时预览尚未跟上
- 真实终端测试用自己的临时文件和独立的 tmux server；开着自动保存，在用户文件上操作会写盘。结束后检查并清理残留的 `nvim --embed`
- headless 不替代完整配置中的鼠标、滚动和视觉验收
- `:PluginManager` 管理插件；`:PackDev [name]` 查看开发重定向；`:PackStats`／`:PackStatsEcho` 查看加载统计
- 类型路径：`bun run scripts/gen-luarc.ts` 或 `:PackGenTypes`
