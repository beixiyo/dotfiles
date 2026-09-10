# 日志服务器操作

仅在需要临时埋点服务器时读取。先定位当前 skill 的 `scripts/debug-server.mjs`，不假定安装在哪个 AI 工具目录。下面的路径、端口和会话名均为示例，按本次环境替换

## 启动与登记

每会话使用唯一 `SESSION`（英文字母、数字、下划线或连字符），所有上报 source 为 `SESSION/tag`，tag 支持英文字母、数字和 `_.:/-`。选择日志目录作为启动 cwd，优先 bun，未安装则 node：

```bash
DEBUG_PORT=9210 DEBUG_LOG=./debug.log bun skill-path/scripts/debug-server.mjs
```

通过当前执行工具保持后台运行。默认端口 `9210`、日志 `./debug.log`；日志父目录须已存在。服务器取得端口和 `debug.log.lock` 独占锁后才轮转：旧日志移为 `debug.log.previous`（替换更早的一轮），当前日志仍为 `debug.log`。复用不会轮转；不同端口也不能共用已锁定的日志文件

正常退出自动释放锁。强制终止可能留下锁：先核对锁内 PID 确实已退出，再移除该锁文件后重试；无法确认则停止，不自动抢锁或杀进程。不要让新旧版服务器共写一个日志文件，升级须等旧实例退出

已有健康实例时，核对 `/health` 的 `logFile`、`port`、`sessions` 是否符合本次工作区；不符合则换端口和日志目录，并同步修改埋点地址。复用或新建后均登记本会话：

```bash
curl -sS -X POST http://127.0.0.1:9210/register \
  -H 'Content-Type: application/json' -d '{"session":"perm-gate-unique"}'
```

## 埋点与采集

按假设选择入口、关键分支或异步两侧，记录实际值和请求 / 会话身份。需要多处上报时可建临时 helper：

```ts
const SESSION = 'perm-gate-unique'
const ENDPOINT = 'http://127.0.0.1:9210/log'

/** 临时诊断上报；避免序列化或传输失败中断业务 */
export function dbg(tag: string, data?: unknown): void {
  try {
    void fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ level: 'debug', source: `${SESSION}/${tag}`, data }),
    }).catch(() => {})
  }
  catch {}
}
```

调用示例：`dbg('permission.required', { kinds, reason })`。多进程可用 `SESSION/M/`、`SESSION/R/` 区分。仅采集必要且可序列化的数据，不记录凭证；异步上报仍有开销，也可能丢失

复现前记下字节游标，随后自行执行场景；只有无法自行操作时才请用户按明确步骤复现：

```bash
CURSOR=$(curl -fsS http://127.0.0.1:9210/offset)
OFFSET=$(printf '%s' "$CURSOR" | node -pe 'JSON.parse(require("fs").readFileSync(0, "utf8")).offset')
INSTANCE=$(printf '%s' "$CURSOR" | node -pe 'JSON.parse(require("fs").readFileSync(0, "utf8")).instance')
# 执行复现后，仅读取自己的增量日志
curl -sS "http://127.0.0.1:9210/logs?since=$OFFSET&instance=$INSTANCE&source=perm-gate-unique/&json=1"
```

响应含 `content`、`instance` 和下一次读取的 `offset`，两者成对保存。读取必传 `source=SESSION/`；使用 `since` 时必传 `instance`。重启后旧实例游标返回 `409 INSTANCE_CHANGED`：重新登记，以响应的新 instance 和 `since=0` 读取，避免跳过重启后的日志。写入 source 缺失或非法返回 `400`，批量先全部校验再写入

异步上报可能晚于页面操作完成，按预期事件有界等待；缺少日志时先排除埋点、序列化、CSP / 网络及传输失败（包括 HTTP 非 2xx），不能直接推断分支未执行。需要更多证据时调整埋点并重新采集

## 验证与收尾

已授权修复时，保留必要埋点，用新游标重跑原场景，对照修复前后的实际行为。验证结束后只移除本次添加的 helper / 调用及资源，保留必要的诊断结论

在线删除接口固定返回 `405`；新一轮使用新游标，不删文件。最后一个会话退出后保留日志，下次新实例启动才归档。更早证据如需长期保留，应在下一次轮转覆盖前另行保存

按会话注销；只有某会话崩溃未注销且确认无人在用时，才向进程发 SIGTERM（服务器会优雅关闭并释放锁）：

```bash
curl -sS -X POST http://127.0.0.1:9210/shutdown \
  -H 'Content-Type: application/json' -d '{"session":"perm-gate-unique"}'
```

`200` 表示最后一个会话已请求关停；`409` 表示本会话已注销，但其他会话仍在使用服务器，正常收尾即可。不要删除他人日志或 PID 文件

## API 速查

| 方法 | 路径 | 用途 |
|------|------|------|
| `POST` | `/log`、`/log/batch` | 单条 `{ level, source, data? }` 或条目数组 |
| `GET` | `/health` | `pid`、`port`、`logFile`、`sessions` |
| `POST` | `/register` | 登记唯一 `{ session }`，重复登记幂等 |
| `GET` | `/offset` | 当前 `{ instance, offset }` |
| `GET` | `/logs?since=…&instance=…&source=…&json=1` | 按会话增量读取及下一游标 |
| `POST` | `/shutdown` | 注销 `{ session }`，无剩余会话时退出 |

服务器仅监听 `127.0.0.1`，内置宽松 CORS；source 是过滤约定而非鉴权，勿采集敏感数据
