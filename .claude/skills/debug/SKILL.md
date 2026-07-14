---
name: debug
description: 当用户需要调试复杂/偶现 Bug，且必须通过运行时真实数据、代码埋点、日志采集、用户复现或跨端/异步时序证据定位问题时使用。触发词包括 debug/调试/日志采集/log collection/运行时上下文。若读代码、跑测试、浏览器自动化或现有日志能定位，先走轻量排查，不启动本 skill
---

## 概述

「日志采集服务器 + 代码埋点 + 迭代分析」三步闭环：先收集运行时上下文，再基于真实数据定位修复

## 分诊：要不要用本 skill（先做这一步）

遵循「不猜测，只验证」。本 skill 是**重型路径**（起服务器 + 埋点 + 让人复现），仅当**同时满足**以下两条才进入执行流程：

1. **AI 自己拿不到运行时上下文**——变量实际值、异步两侧时序、多进程/跨端状态，靠读代码、`grep`、跑测试都无法确定
2. **需要人主动复现**——交互触发、特定环境、偶现 Bug，AI 无法自动重放

否则先走**轻量静态排查**，不要起服务器：

- 读相关代码、按调用链推理可能的原因路径
- 索要无法自行获取的信息（环境变量、依赖版本、配置、现有日志）
- 能自动化就自动化：跑测试复现、浏览器自动化、查 DevTool

静态分析能定位 → 直接修；确实需要运行时真实数据且必须靠人复现 → 才往下走 Phase 0

## 执行流程

### Phase 0: 会话身份（并发前提）

取一个唯一标识 `SESSION`（kebab，体现主题，如 `perm-gate`），所有埋点 `source` 统一加前缀 `SESSION/`——这是多会话隔离（过滤读、范围清空）的根基

### Phase 1: 启动 / 复用服务器

在**工作区根目录**后台启动（优先 bun，未装则 node），幂等：已有健康实例自动复用，不重复起、不误杀

```bash
# 默认：端口 9210，日志 ./debug.log
bun ~/.claude/skills/debug/scripts/debug-server.mjs &

# 仅当调试「不同 app / 工作区」时才换端口和日志
DEBUG_PORT=9211 DEBUG_LOG=./logs/debug.log bun ~/.claude/skills/debug/scripts/debug-server.mjs &
```

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `DEBUG_PORT` | `9210` | 监听端口 |
| `DEBUG_LOG` | `./debug.log` | 日志路径（相对启动时 cwd） |

`GET /health` 验证已启动后，**登记本会话**（引用计数，防止收尾时被别人提前关停）：

```bash
curl -s -X POST http://localhost:9210/register -H 'Content-Type: application/json' -d '{"session":"perm-gate"}'
```

> 被调试 app 的埋点端口通常写死，故多会话调试**同一个 app** 必然共享同一 server 和 `debug.log`，换端口无效——隔离靠 `SESSION/` 前缀。只有调**不同 app/工作区**才用 `DEBUG_PORT`+`DEBUG_LOG`

### Phase 2: 分析并埋点

分析可能的原因路径，在**关键节点**（入口、分支、出口、异步两侧）插入上报，采集变量**实际值**而非"到达了这里"

**先一次性建一个埋点 helper**（临时文件，排查完删），之后每处埋点只写一行 `dbg('tag', data)`——`SESSION/` 前缀自动带上（省 token + 保证隔离），`tag` 即定位锚点（源码搜 tag 即可回跳）：

```ts
// __dbg.ts —— 临时调试埋点，排查完整体删除
const SESSION = 'perm-gate'                 // 改成你的会话标识
const ENDPOINT = 'http://localhost:9210/log'

/** fire-and-forget 上报；tag 作为 source 后缀兼定位锚点 */
export function dbg(tag: string, data?: unknown): void {
  void fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ level: 'debug', source: `${SESSION}/${tag}`, data }),
  }).catch(() => {})
}
```

埋点处一行：`dbg('permission.required', { kinds, reason })`。多进程（如 Electron 主/渲染）各放一份，子前缀区分（`${SESSION}/M`、`${SESSION}/R`）。其他语言照此封装一个 `dbg(tag, data)` 即可

### Phase 3: 运行 & 采集（游标读，不清空）

先记下当前游标，复现后只读这次窗口的增量：

```bash
OFFSET=$(curl -s http://localhost:9210/offset | sed 's/[^0-9]//g')
```

用 `AskUserQuestion` 列出埋点位置、请用户复现 Bug，**等用户确认**，不自行假设

### Phase 4: 分析日志（增量 + 按会话过滤）

只读自己的增量与前缀，绝不整读、绝不清空：

```bash
curl -s "http://localhost:9210/logs?since=$OFFSET&source=perm-gate/"
```

看执行顺序、变量值、缺失日志（说明未走到该路径）、error/warn。已定位 → Phase 5；要补信息 → 调整埋点（如需清噪声用 `DELETE /logs?source=SESSION/`，**勿整清**），回 Phase 3 重记游标

### Phase 5: 修复 & 验证

实施修复，**保留埋点**，只清自己旧日志（`DELETE /logs?source=SESSION/`，或换新游标）。用 `AskUserQuestion` 请用户复现验证：已修复 → Phase 6；未修复 → 回 Phase 2

### Phase 6: 清理（只收自己的）

1. 删掉 `__dbg` helper 文件，移除本会话的 `dbg(` 调用（`grep -rn "dbg(" 源码目录` 逐处定位）；共享文件别整段删
2. 只清自己的行：`curl -s -X DELETE "http://localhost:9210/logs?source=SESSION/"`
3. 注销并请求关停（引用计数）：

```bash
curl -s -X POST http://localhost:9210/shutdown -H 'Content-Type: application/json' -d '{"session":"perm-gate"}'
```

`{ok:true}` = 最后一个会话，已关停（PID 自清）；`409` = 还有他会话在用，保持运行、你正常收尾即可。`debug.log` 可能含他人记录，别无条件删

## 服务器 API 速查

| 方法 | 路径 | 说明 |
|------|------|------|
| `POST` | `/log` | 单条日志 `{ level, source, data? }` |
| `POST` | `/log/batch` | 批量日志 `Array<LogEntry>` |
| `GET` | `/offset` | 当前日志字节偏移（复现前记下） |
| `GET` | `/logs` | 读取；query：`since=<offset>` 增量、`source=<前缀>` 过滤、`json=1` |
| `DELETE` | `/logs` | 范围清空，必须带 `source=<前缀>`（并发安全）；整清需显式 `all=1` |
| `GET` | `/health` | 健康检查（`pid`/`port`/`logFile`/`sessions`） |
| `POST` | `/register` | 登记会话 `{ session }`（引用计数 +1） |
| `POST` | `/shutdown` | 关停 `{ session?, force? }`；带 `session` 减引用，仍有他会话且非 force 返回 409 |

## 多会话并发（铁律）

端口 / `debug.log` / PID 三个共享单例会引发数据竞争，遵守即安全：

- 每会话一个 `SESSION`，埋点 `source` 全带 `SESSION/` 前缀
- 清日志只用 `DELETE /logs?source=SESSION/`（范围清空）；整清需显式 `all=1`，多会话下绝不用（会抹掉别人日志）
- 读用游标增量（`/offset` + `/logs?since=&source=`），不整读猜归属
- 关停走引用计数，别 `kill` 或无条件关共享 server，别删别人 PID
- 清理只删自己埋点；`/health` 是 `running` 就复用，别重起

## 注意事项

- 仅监听 `localhost`，CORS 已内置
- 埋点用 fire-and-forget（不 await），不影响业务逻辑
- 日志格式：`[ISO时间] LEVEL [source] | data`（`source` = `SESSION/tag`）
- 工作区产物（`debug.log`、`.debug-server.<port>.pid`）建议加入 `.gitignore`
