# Quickshell 配置说明（AGENTS）

本目录是 [Quickshell](https://quickshell.org) 配置,采用**统一 config root** 组织,目前包含一个剪贴板弹窗(`clipboard/`),并预留了跨组件复用的公共库(`Common/`)

动手前请先读完本文件,尤其是「场景坑」一节——里面几条都是踩过的雷,不读大概率复现

## 目录结构

```
~/.config/quickshell/
├── shell.qml                 # 唯一入口:按 QS_COMPONENT 用 Loader 派发到具体组件
├── qs-popup                  # 启动脚本(在 PATH 里):qs-popup <组件名>
├── Common/                   # 公共库 → import qs.Common(首字母大写文件自动可导入)
│   ├── Colors.qml            # 配色单例:FileView 读 colors.json,缺失则回退 Catppuccin
│   ├── colors.json           # matugen 按壁纸生成(gitignore,机器相关)
│   ├── Theme.qml             # 设计系统单例:语义配色 + 间距/圆角/字号/动画 + alpha()
│   ├── Format.qml            # 无状态:字节/时长格式化
│   ├── Fuzzy.qml             # 无状态:模糊匹配
│   ├── ScreenModel.qml       # 多屏选择
│   └── components/           # 通用原子组件 → import qs.Common.components
│       ├── GlassPanel.qml    #   玻璃面板(描边+落影+内描边)
│       ├── SearchBox.qml     #   搜索条(props 驱动)
│       └── TagFilterBar.qml  #   标签过滤条(props 驱动)
└── clipboard/                # 剪贴板 app → import qs.clipboard(详见其 README.md)
    ├── Clipboard.qml         #   主 UI 组装
    ├── ClipboardController.qml  # 业务/进程/调度(Scope)
    ├── ClipboardLogic.js     #   .pragma library 纯函数
    ├── ClipDelegate.qml      #   列表卡片
    └── PreviewOverlay.qml    #   全屏预览
```

## 启动方式

```bash
qs-popup clipboard      # = QS_COMPONENT=clipboard qs -p ~/.config/quickshell/shell.qml -n
```

`shell.qml` 读 `QS_COMPONENT` 环境变量,用 `Loader` 只实例化被选中的组件,弹窗按需启动、退出即关

**新增一个 app**:在 `<name>/` 下写一个首字母大写的主组件(如 `Foo.qml`),在 `shell.qml` 里加一段 `Loader { active: component === "foo"; sourceComponent: ... }` 即可,公共库直接 `import qs.Common`

## 配色系统

```
壁纸 ──matugen──> Common/colors.json (gitignore)
                        │ FileView 读取
   Common/Colors.qml ───┤ 读到 → 用壁纸色
   (提交进仓库)          └ 读不到 → JsonAdapter 默认值 = Catppuccin Mocha 兜底
                        │
   Common/Theme.qml ────> 语义映射 + token ──> 各组件 Theme.xxx
```

- matugen 模板:`~/.config/matugen/templates/quickshell-colors.json`,config.toml 的 `[templates.quickshell]` 输出到 `Common/colors.json`
- 换壁纸后 matugen 重写 `colors.json`,`Colors.qml` 的 `FileView.watchChanges` 会实时重载
- 改兜底主题:编辑 `Colors.qml` 里 `JsonAdapter` 各 `property string` 的默认值

## 关键约定

| 约定 | 说明 |
|------|------|
| 不写 qmldir | Quickshell 的 QmlScanner 自动合成;手写反而会**关闭**自动合成 |
| 文件命名 | 可导入的类型/组件**首字母大写**;子目录名即模块路径(`Common/` → `qs.Common`) |
| 单例 | 全局状态/工具用 `pragma Singleton` + `Singleton{}`(Theme/Colors/Format/Fuzzy/ScreenModel) |
| 纯函数 | 无状态算法放 `.pragma library` 的 `.js`;依赖运行时状态/Theme 的留在实例化对象里 |
| 图标字体 | 统一用 `Theme.iconFont` |

## 场景坑（务必先看）

1. **统一 config root 的由来**:Quickshell 的 config root = `shell.qml` 所在目录,且**会拦截(blackhole)root 之外的 import**。所以想让多个 app 共享 `import qs.Common`,**只能**把它们收进同一个 root(本配置即如此)。「在 app 旁边平级放 Common/」行不通

2. **`Variants` 委托内对兄弟对象 id 的直接绑定不具响应性**。例:`PanelWindow`(Variants 委托)里写 `visible: clip.loading`、`model: clip.filteredItems`(`clip` 是委托外的兄弟对象 id) 只会在创建时求值一次,之后控制器属性变化**不更新 UI**(典型症状:一直「加载中」、列表空)
   修法:在委托上用属性持有控制器 `property var ctl: clip`,绑定走属性链 `ctl.xxx`(属性链会正确订阅变化)。引用**文件根 id**(`root`) 则天然响应式

3. **子组件属性名勿与外层 id 同名**。如子组件声明 `property var controller` 又写 `controller: controller`,右值会自引用遮蔽成 undefined。用不同名字(本配置控制器 id 叫 `clip`)

4. **图标字体区分清楚**:
   - `iconFont = "Symbols Nerd Font"`:纯图标字体(`SymbolsNerdFont-Regular.ttf`),图标字形覆盖最全
   - `monoFont = "Maple Mono NF"`:等宽编程字体,同时内嵌 NF 图标,也可作为备用 iconFont
   - 坑:`"Symbols Nerd Font Mono"` 是 Symbols 字体的 Mono 变体,**本机未装**;fontconfig 会回退到 Noto Sans,图标变空方块。别把它和 `"Maple Mono NF"` 混淆

5. **写图标字形可能被工具吞掉**。直接在文件里输入 PUA 字形(如垃圾桶 )有时会落盘成空串。可靠做法:写 `\uXXXX` 转义(QML 的 JS 解析器会正确解释);用脚本注入时按字面 ASCII 写 `\u`

6. **`FileView.path` 用绝对文件系统路径**。`Qt.resolvedUrl` 在 Quickshell 的 `qs://` 拦截下拿不到真实文件路径,FileView 读不到。用 `Quickshell.env("XDG_CONFIG_HOME")...` 拼绝对路径

7. **`.pragma library` 的 JS** 可访问 `Qt` 全局对象(如 `Qt.rgba`),但**访问不到** QML 实例 / 导入方的属性(只能靠参数传入)

8. **控制字符正则**(`\x00`/`\x1a` 等)用 `String.fromCharCode` 构造,别让源码里出现不可见字节

## 调试

- 加载并看日志:`qs -p ~/.config/quickshell/shell.qml -n`(前台,Ctrl-C 退出);持久日志在 `/run/user/<uid>/quickshell/by-id/<id>/log.qslog`
- 列实例 / 杀进程:`qs list --all` / `qs kill --all`
