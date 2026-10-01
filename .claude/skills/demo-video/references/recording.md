# 录制、编码与验证

## 抓帧原理

- **用 CDP `Page.startScreencast`，不用 Playwright `recordVideo`**：后者码率低、帧率不稳、画面糊。screencast 配合 `deviceScaleFactor: 2` 输出高清 JPEG，每帧带 `metadata.timestamp`
- screencast **只在画面变化时出帧**，间隔不均匀。不能按固定帧率拼接，要把每帧真实停留时长写进 ffmpeg concat 清单：

  ```
  file 'f000001.jpg'
  duration 0.033412
  file 'f000002.jpg'
  duration 1.204000   ← 静止段一帧顶很久
  ...
  file 'f000999.jpg'  ← concat 忽略最后一条 duration，末帧要重复一次
  ```
- 每帧必须 `Page.screencastFrameAck`，否则浏览器停止推帧
- 时间轴统一用 epoch 秒：screencast 时间戳、页面 `performance.timeOrigin + performance.now()`、Node `Date.now()` 都来自系统时钟，可直接比较
- 帧写盘异步进行，停止后统一等待；临时目录放 `os.tmpdir()`，finally 里清理
- 裁剪坐标 = CSS 坐标 × (实际帧宽 / 视口宽)：以第一帧真实宽度推算比例，screencast 被缩放时不会错位；裁剪区域取偶数并钳制在帧内
- 只按目标元素撑开视口，不要按整页 `scrollHeight` 撑：整页过高时 screencast 会缩小输出，清晰度下降、裁剪越界

## 无缝循环

1. 页面每轮开始把计数属性 +1；录制端用 MutationObserver 观察**整个文档**（subtree），只接受恰好 +1 的变化。只盯单个元素时，热更新或重渲染替换节点就会丢边界、录制超时
2. 跳过首个不完整循环，录「第 1 个边界 → 第 2 个边界」；起点画面取边界前最后一帧
3. 页面侧保证首尾画面相同：结尾淡出到空白，淡出完全结束后才进入下一轮。验证：抽首帧和末帧并排对比

## GIF 取舍

体积主因是**整幅运动**（镜头推拉、滚动）：每帧所有像素都变，`diff_mode=rectangle` 失效。实测（720px，18s 含 6 次推镜）：

| 调整 | 体积变化 | 代价 |
|---|---|---|
| fps 25 → 15 → 12 | 12.7 → 7.8 → 6.4 MB（800px/256 色） | 12fps 下 1s 缓动仍连贯；更低会顿 |
| 宽度 800 → 720 | 约 -17% | 640 时小字明显糊 |
| 颜色 256 → 128 → 64 | 6.4 → 4.4 → 3.6 MB | 64 色在大面积阴影、光晕上出现明显色带；128 平滑 |
| 抖动 none / bayer / sierra2_4a | none 最小 | 抖动反而更大且文字变软（平涂 UI 不需要抖动） |
| `mpdecimate` 去重帧 | 约 -1% | 几乎无效，静止段本来就只有一帧 |
| `palettegen stats_mode=diff` vs `full` | diff 约 -3% | 无 |

调优顺序：先降 fps，再降颜色（盯阴影是否出色带），最后降宽度。README 要求清晰时直接给 MP4（体积约为 GIF 的一半且画质更好）；GitHub README 只能内嵌 GIF/图片，MP4 需要上传到 issue/PR 生成 user-attachments 链接

## ffmpeg 配方

```bash
# 抽帧拼图验证（第 30/90/150 帧横排）
ffmpeg -v error -y -i out.gif -vf "select='eq(n\,30)+eq(n\,90)+eq(n\,150)',scale=480:-1,tile=3x1:padding=4" -frames:v 1 -update 1 sheet.png

# 首尾帧对比（N 为总帧数，ffprobe -count_frames 取得）
ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 out.gif

# 已有视频转 GIF（两段式调色板）
ffmpeg -i in.mp4 -filter_complex "fps=12,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff:max_colors=128[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" -loop 0 out.gif

# 剪切 3s–10s 并 1.5 倍速
ffmpeg -ss 3 -to 10 -i in.mp4 -vf "setpts=PTS/1.5" -an out.mp4

# 网页友好 MP4
ffmpeg -i in.mov -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -movflags +faststart -an out.mp4
```

## 验证清单

- 开场、关键动作、运动中段、结尾各抽一帧；明暗主题、每种语言各一份
- 首尾帧并排对比（循环素材）
- 报告时长、尺寸、体积；体积超目标时说明取舍而不是直接交付
- 结束后确认自动启动的服务已关闭：`lsof -nP -iTCP:<port> -sTCP:LISTEN`
