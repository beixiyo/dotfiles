# AGENTS.md — vv-* 插件共享开发规范

本文定义 `vendors/vv-*.nvim` 的共享边界。具体插件的公共 API、默认值和行为由各仓库 README 与源码负责；修改时继续读取目标仓库内更近的 AGENTS/README

## 先查 vv-utils

实现共享机制前先读 [vv-utils 中文 README](vv-utils.nvim/README.zh-CN.md)。它是当前模块和 API 的唯一索引，不在本文复制完整列表

常见应优先复用的机制包括：

- 项目根、路径和 glob
- fs 原语、事务和撤回
- Git 状态、diff、符号和共享高亮
- LSP WorkspaceEdit、Code Action、fix 与文件操作协议
- diagnostics 聚合
- history 和持久 state
- timer、loading、input、prompt、match
- keymap 生命周期、help panel 和 tree panel
- UI window chrome、mouse guard 和 layout-safe buffer 删除
- 跨平台打开、执行、下载和终端拖放
- bigfile、format、animate 和 scroll

只有满足以下条件才抽进 `vv-utils`：

- 机制不依赖具体 vendor 的业务 state、filetype 或渲染结构
- 已有第二个 caller，或第二个 caller 已进入当前实现范围
- 能以参数、回调、handle 或 adapter 暴露策略

订阅 autocmd、业务 debounce、调用 render 和持有业务 state 通常留在 vendor 的薄适配层

## 配置与类型

- 解析后的配置类型为 `VVXxxConfig`，字段必填，读取处不写 `or DEFAULT`
- 默认值只放在模块私有 `local defaults` 中，并在字段上用 `@default` 说明；不得在读取处或其他模块重复默认值
- 输入类型为 `VVXxxOpts`，由 `VVXxxConfig` 派生：顶层写 `---@class (partial)`，每个嵌套表各写一行 `(partial)` 声明，禁止复制叶子字段
- `setup(opts)` 入参标 `VVXxxOpts?`，用 `vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})` 合并，无返回值，调用方读取配置用 `get_config()`
- 禁用语义统一用 `false`，类型写成 `Foo|false`；nil 表示未配置、取默认值；文档中禁止写"nil 则禁用"
- 运行时派生值（如 state、provider、handle）在 `defaults` 中保持 nil，合并之后再赋值，不进入 `Opts`
- 运行时依赖（如 state 句柄）通过 `setup(opts, deps)` 的第二参数注入，类型为 `VVXxxDeps`，不进入 `VVXxxOpts`。lazy 与 pack 的默认调用只传 `setup(opts)`，第二参数为 nil，此时插件使用内置默认
- 跨仓库子配置：调用方传用户原始子表，由被调用方自己归一化默认值；不得把已解析的默认值转交给其他仓库
- 配置存为模块私有 `local config`
- `get_config()` 返回 deepcopy，避免调用方修改内部状态
- 生命周期 API 成对且幂等
- 可见 UI 使用 `open/close/toggle`
- 原子编辑能力可以暴露语义明确的业务动作
- 纯数据或一次性动作不伪造无意义生命周期

## User command 与 keymap

- 命令使用 `VV<Plugin><Action>`，例如 `VVExplorerToggle`
- 有意义且适合 Ex 调用的公共动作应提供 command，但不要求为每个内部函数建命令
- spec `cmd` 必须与插件真实注册的命令一致，否则 lazy command 无法重放
- 全局快捷键由 dotfiles spec 的 `keys` 负责
- 插件 setup 不应偷偷注册不可关闭的全局键
- 插件自己的 buffer-local 交互在 attach/open 生命周期中注册，并在资源释放时清理
- keymap `desc` 使用 `vv-<plugin>: <action>` 前缀，便于 `help_panel` 反读和分组

## 高亮和 UI

- 快捷键展示统一使用 `vv-utils.keys.display(lhs)`；需要「动作 + 快捷键」文本时使用 `vv-utils.keys.hint(action, lhs)`
- 共享 Git 状态装饰使用 `vv-utils.git`
- 批量高亮使用 `vv-utils.hl.register`，由它处理 `default=true` 和 `ColorScheme`
- 通用树侧栏优先使用 `vv-utils.tree_panel`
- 通用过滤输入优先使用 `vv-utils.prompt` / `vv-utils.input`
- nofile 面板使用 `vv-utils.ui_window` 管理 window chrome
- 替换主窗 buffer 后按 [bufdelete 边界](vv-utils.nvim/docs/bufdelete.md) 判断是否清理旧空 buffer

## 鼠标面板

- 需要“光标已定位后再动作”的单击使用 `<LeftRelease>`
- 右键需要落点时使用 `<RightMouse>` 配合 `vim.fn.getmousepos()`
- 不假设 buffer-local Nop 能拦住所有跨窗口拖拽
- nofile 面板需要禁止拖拽或多击进入 Visual 时，使用 `vv-utils.mouse.block_visual_drag(buf)`
- 双击、三击、四击是否映射由具体面板交互决定，不作为所有 vendor 的硬编码策略

## 生命周期

- timer、autocmd、listener、buffer、window 由创建者清理
- `open/close`、`attach/detach`、`enable/disable` 保持幂等
- 异步结果写回前验证资源仍有效，并丢弃过期请求结果
- 不用全局 `BufHidden` 一类高频 hook 猜测具体业务生命周期
- 重要副作用通过命名、返回 handle、类型或 README 明确

## 验证

- vv 插件开发测试统一使用 [vv-utils 共享测试入口](vv-utils.nvim/dev/test/README.md)；各仓 `tests/run.sh [过滤词]` 定位共享入口，`tests/env.sh` 声明已有依赖的自动发现和环境变量覆盖策略
- `tests/**/test_*.lua` 返回 mini.test 的具名集合，收集阶段只注册用例；用例名称、断言说明和测试注释使用中文
- 每个场景独立建立必要前置条件；窗口、buffer、模块状态和异步资源优先在独立 Neovim 子进程中验证，失败路径同样清理 fixture 与进程
- child 启动前、被测模块加载前，将 cwd、HOME、XDG 持久目录和临时文件根设到该 case 独立的 `/tmp` fixture；文件路径前置值必须非空，不能让 nil 被 Neovim 转为 `v:null` 后写入真实仓库
- 保留真实行为和高信号回归，不为常量、导出、简单 getter 或重复实现分支新增测试
- 修改共享 API 时同时搜索全部 caller，并分别在受影响仓库验证
- 注意每个 vendor 可能是独立 Git 仓库，不跨仓混合暂存或提交
