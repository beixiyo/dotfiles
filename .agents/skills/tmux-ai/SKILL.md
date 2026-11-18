---
name: tmux-ai
description: 使用 tmux 协调多个 AI 进程互相协作或 review，子 AI 工作时后台 bash 轮询完成状态，完成后通知主 agent。必须由用户自己调用
---

## 目标

在 tmux 中拉起子 AI，发送任务，`spawn.sh` 内部自动启动后台 `watch.sh` 轮询。子 AI 完成后，`watch.sh` 用 `tmux send-keys` 通知主 agent，主 agent 再读取结果文件。整个等待过程由纯 bash 完成，主 agent 零 token 消耗

---

## 工具脚本（均在 `scripts/` 目录，相对于本 skill）

| 脚本 | 用途 |
|------|------|
| `spawn.sh <main_pane> [split-window args...]` | 创建新 pane（默认右分屏 `-h`）+ 生成 session 目录 + **自动启动 watch.sh**，输出 `PANE_ID` 和 `SESSION_DIR` 两行 |
| `send.sh <pane_id> <消息>` | 向 pane 发送文本并回车（`-l` literal，特殊字符安全） |
| `watch.sh <main_pane> <session_dir> [poll_interval]` | 后台轮询 `$SESSION_DIR/done`，完成后 `tmux send-keys` 通知主 agent（由 spawn.sh 自动调用，无需手动启动） |
| `wait-ready.sh <pane_id> <keyword> [timeout] [poll_interval] [delay_after]` | 轮询 pane 内容直到出现 keyword，等待 delay 后退出。默认超时 30s，轮询 1s，delay 3s |
| `read.sh <pane_id> [行数]` | 抓取 pane 屏幕内容，用于：1) 查看其他 pane 的实时输出 2) `output.md` 不存在时的降级读取 |

### 已验证 CLI 适配表

| CLI | 启动命令 | wait-ready keyword | delay |
|-----|---------|-------------------|-------|
| opencode | `opencode` | `Ask anything` | 3s |
| claude code | `claude` | `❯` | 3s |

> 接入新 CLI 时，手动启动一次观察 TUI 就绪后的**稳定特征文字**，填入 keyword 即可

---

## 架构

```
spawn.sh 内部自动启动 watch.sh，主 agent 只需调用 spawn + send

主 agent pane                watch.sh (自动)              子 AI pane
     |                            |                          |
     |-- spawn.sh(main_pane) --> [创建 pane + 启动 watch]    |
     |   返回 SUB_PANE,          | 后台每 5s 检查 done       |
     |         SESSION_DIR       |                          |
     |-- send.sh 发任务 ----------------------------------------->|
     |                           |                          | working...
     | [空闲，等通知]             |                          |
     |                           | done 出现                |
     |<-- tmux send-keys <------- [AI_DONE] /tmp/ai-collab/xxx
     | 收到通知                  | (退出)                   |
     |-- cat output.md           |                          |
```

---

## Session 目录

- 路径：`/tmp/ai-collab/20260423-143022-8421/`（时间戳 + PID，spawn 时生成）
- `output.md`：子 AI 写入结果
- `done`：子 AI 写入完成标记（`touch done`）
- **不自动清理**，随时可查看历史；手动清理：`rm -rf /tmp/ai-collab/`

---

## 完成检测

唯一信号：`$SESSION_DIR/done` 文件存在

`watch.sh` 由 `spawn.sh` 自动启动，主 agent 无需手动管理。子 AI 没写 `done` 就一直等，不误报

---

## 标准工作流

```bash
SCRIPTS=".claude/skills/tmux-ai/scripts"

# 1. 获取当前 pane ID（主 agent 自己的）
MAIN_PANE=$(tmux display-message -p "#{pane_id}")

# 2. 拉起子 AI pane（默认右分屏，watch.sh 自动启动）
#    spawn.sh 会写 $SESSION_DIR/session.env，后续步骤可直接 source
_out=$(./$SCRIPTS/spawn.sh "$MAIN_PANE")
SUB_PANE=$(echo "$_out" | sed -n '1p')
SESSION_DIR=$(echo "$_out" | sed -n '2p')

# 后续 Bash 调用中可直接 source，无需重复声明变量：
# source $SESSION_DIR/session.env
# → 自动获得 MAIN_PANE, SUB_PANE, SESSION_DIR, SCRIPTS

# 3. 【必须】先 cd 到目标项目目录，再启动子 AI（合并为一条命令）
./$SCRIPTS/send.sh "$SUB_PANE" "cd /path/to/project && opencode"

# 4. 等待子 AI 就绪（keyword 按实际 CLI 调整）
./$SCRIPTS/wait-ready.sh "$SUB_PANE" "Ask anything" 30 1

# 5. 发送任务（prompt 里指定输出路径和 done 标记，路径必须用绝对路径）
./$SCRIPTS/send.sh "$SUB_PANE" "请 review ai-tools/send.sh，把结果写入 $SESSION_DIR/output.md，完成后执行 touch $SESSION_DIR/done"

# 主 agent 现在可以做别的事，等待 [AI_DONE] 通知
```

收到 `[AI_DONE] /tmp/ai-collab/xxx` 通知后：

```bash
# 5. 读取结果（优先读文件）
cat "$SESSION_DIR/output.md"

# 6. 若 output.md 不存在（AI 忘写文件），降级抓屏
[ ! -f "$SESSION_DIR/output.md" ] && ./$SCRIPTS/read.sh "$SUB_PANE" 200
```

### 使用 read.sh 读取 pane 内容

`read.sh` 用于直接抓取任意 pane 的屏幕文字，适用于：
- **查看子 AI 实时状态**：任务进行中想看子 AI 当前在干什么
- **读取非文件输出**：子 AI 的结果直接打印在终端，没有写入文件
- **降级读取**：子 AI 完成但忘记写 `output.md`

```bash
# 查看子 AI pane 最近 50 行输出
./$SCRIPTS/read.sh "$SUB_PANE" 50

# 查看子 AI pane 最近 200 行输出（更完整）
./$SCRIPTS/read.sh "$SUB_PANE" 200
```

> **注意**：`read.sh` 受 tmux 滚动缓冲区限制，输出过长可能截断。优先使用文件（`output.md`）传递结果

---

## 执行步骤

1. 确认前提：`[ -n "$TMUX" ]`（在 tmux 中）；子 AI 工具已安装
2. 获取 `MAIN_PANE`：`tmux display-message -p "#{pane_id}"`
3. `spawn.sh "$MAIN_PANE"` 同时拿 `SUB_PANE` + `SESSION_DIR`（默认右分屏，watch.sh 自动启动）
4. `send.sh` cd 到项目目录 + 启动子 AI
5. `wait-ready.sh` 轮询等待子 AI 就绪（按 CLI 类型传不同 keyword）
6. `send.sh` 发任务，prompt 里用**绝对路径**写 output 和 `touch done`
7. 收到 `[AI_DONE]` 通知后读 `output.md`，不存在则降级 `read.sh`

---

## 边界情况

| 情况 | watch.sh 行为 | 处理方式 |
|------|-------------|---------|
| 正常完成 | 检测到 `done`，发 `[AI_DONE]`，自动退出 | 主 agent 读 `output.md` |
| AI 忘写 `done` | 一直轮询，不退出 | 用户手动 kill watch.sh 进程 |
| 不在 tmux 中 | spawn 前失败 | 提前检查 `[ -n "$TMUX" ]` |
