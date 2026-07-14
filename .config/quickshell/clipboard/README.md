# 剪贴板组件（clipboard）

基于 **cliphist + Quickshell** 的剪贴板弹窗:HUD 式搜索、类型分类、图片/视频/HTML 预览、置顶收藏、二次激活复制(回写系统剪贴板)

启动:`qs-popup clipboard`(详见上级 `../AGENTS.md`)

## 文件职责

| 文件 | 职责 |
|------|------|
| `Clipboard.qml` | 主 UI 组装:窗口定位、入场动画、快捷键、磨砂模糊、组装搜索框/过滤条/列表/预览 |
| `ClipboardController.qml` | 业务核心(`Scope`,非可视):列表加载、分块解析、异步解码、mime 探测、缩略图、过滤排序、复制/删除、**置顶** |
| `ClipboardLogic.js` | `.pragma library` 纯函数:文本清洗、类型分类、颜色解析、HTML 解析、路径提取、二进制元数据 |
| `ClipDelegate.qml` | 列表单项卡片(类型图标 / 缩略图 / 预览文本 / 置顶·删除按钮) |
| `PreviewOverlay.qml` | 全屏详情预览(图片 / GIF / 视频+元数据 / 多文件 / 文本) |

## 数据流

```
cliphist list ──> 分块解析(首屏 15 条立即渲染,其余分帧)
                    ├─> 异步解码(cliphist decode):补全搜索索引、HTML 图片/纯文本、文件路径
                    ├─> mime 探测(file --mime-type):精确分类文件类型
                    ├─> 图片解码(cliphist decode → 缓存目录):二进制图片缩略图
                    └─> 视频缩略图(ffmpeg/ffmpegthumbnailer)+ 元数据(ffprobe)
搜索/标签 ──> filterItems():置顶项排最前 + 历史项(关键词直配优先,其次模糊匹配)
```

## 存储位置

| 用途 | 路径 | 是否持久 |
|------|------|----------|
| 配置本体 | `~/.config/quickshell/clipboard/` | 提交进仓库 |
| **置顶清单** | `~/.local/share/qs-clipboard/pins/pins.json` | 持久(机器本地) |
| **置顶图片快照** | `~/.local/share/qs-clipboard/pins/<id>.<ext>` | 持久(机器本地) |
| 解码图片 / 视频缩略图缓存 | `$XDG_RUNTIME_DIR/qs-clipboard/`(如 `/run/user/1000/qs-clipboard/`) | 临时(重启即清) |
| 防同步竞态的内容 hash | `$XDG_RUNTIME_DIR/clipboard-sync/last_hash` | 临时 |

## 置顶（收藏）与清空的关系

核心:**置顶项与 cliphist 历史完全解耦,独立持久化**(快照存到 `~/.local/share/qs-clipboard/pins/`),即使 cliphist 清空/轮换也不丢

| 操作 | 对历史(cliphist) | 对置顶 |
|------|------|------|
| 显示 | 历史项排在置顶项之后 | 排最前;同一条同时在两边时按 id 去重,只显示置顶那份 |
| **清空**(垃圾桶按钮,二次确认) | `cliphist wipe` + 清缓存 | **保留**;并回收 `pins.json` 未引用的孤儿快照 |
| 删除单项 | 普通项 → `cliphist delete` | 置顶项的删除按钮 = **取消置顶**(不删 cliphist) |
| 取消置顶 | — | 移出 pins.json,并删除其图片快照(孤儿回收) |
| 复制 | `cliphist decode` 当场解码 | 走持久快照,**不依赖** cliphist 条目是否还在 |

> 孤儿快照回收(`gcOrphanPins`) 在**取消置顶 / 清空 / 启动加载**时各跑一次,删掉 pins 目录里 `pins.json` 已不再引用的文件

## 二次激活复制（回写剪贴板）

选中条目后,把内容重新写回系统剪贴板(以便接着 `Ctrl+V` 粘贴):

- **双通道**:`wl-copy`(Wayland)+ `xclip`(X11 兜底,自动探测 `:0`~`:3`),尽量保留原始 MIME
- **防竞态**:写入前先把内容 hash 存到 `clipboard-sync/last_hash`,规避同步守护进程把刚写入的内容当成新条目重新入库
- **图片/文件**:图片优先按 image MIME 写;某些场景(如 QQ 缩略图)按 `text/uri-list` 写文件 URI(可用 `QS_IMAGE_FILE_MODE=uri|image|auto` 控制)
- 复制进程用 `setsid` 脱离,避免随弹窗退出被杀

## 环境变量

| 变量 | 默认 | 作用 |
|------|------|------|
| `QS_POS` | `center` | 窗口位置:`center` / `top-left` / `bottom-center` … |
| `QS_MARGIN_T/R/B/L` | `8` | 贴边时的外边距 |
| `QS_TARGET_OUTPUT` | (首个屏幕) | 指定显示在哪个输出(如 `DP-1`) |
| `QS_CLIPBOARD_LIST_LIMIT` | `750` | 最多加载多少条历史 |
| `QS_CLIPBOARD_DECODE_CHUNK` | `24` | 异步解码每批条数 |
| `QS_CLIPBOARD_PARSE_CHUNK` | `60` | 分帧解析每批条数 |
| `QS_CLIPBOARD_SEARCH_TEXT_LIMIT` | `20000` | 单条解码用于搜索索引的最大字节 |
| `QS_IMAGE_FILE_MODE` | `auto` | 图片文件复制策略:`uri` / `image` / `auto` |

## 快捷键

| 键 | 动作 |
|----|------|
| 输入 | 实时搜索;`#标签 关键词` 可内联按标签过滤 |
| `↑`/`↓` 或 `Ctrl+P`/`Ctrl+N` | 上下移动高亮 |
| `Enter` | 复制选中项并关闭 |
| `Alt+P` | 预览选中项 |
| 右键条目 | 预览 |
| 悬停条目 → 图钉 / 垃圾桶 | 置顶 / 删除 |
| `Esc` | 关预览;再按关窗口 |

## 外部依赖

`cliphist`、`wl-copy`(wl-clipboard)、`xclip`(可选,X11 兜底)、`file`、`ffmpeg` 或 `ffmpegthumbnailer`(视频缩略图)、`ffprobe`(视频元数据)、`xdg-open`、`xdg-user-dir`、`Symbols Nerd Font`(图标字体)
