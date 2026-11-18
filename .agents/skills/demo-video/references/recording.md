# 录制、编码与验证

## 自行实现 CDP 截帧时

- `scripts/record.ts` 使用 CDP `Page.startScreencast`，可控制帧质量并取得 `metadata.timestamp`。使用现成录制器时无需重写此流程；质量取决于实际尺寸与编码参数，不能仅按工具名称判断。DPR和最终编码宽度分别控制，需核验成片
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

体积主因是**整幅运动**（镜头推拉、滚动）：每帧所有像素都变，`diff_mode=rectangle` 失效。以下是一次720px、18s、含6次推镜的样例测量，用于说明取舍方向，不是其他素材的体积保证：

| 调整 | 体积变化 | 代价 |
|---|---|---|
| fps 25 → 15 → 12 | 12.7 → 7.8 → 6.4 MB（800px/256 色） | 12fps 下 1s 缓动仍连贯；更低会顿 |
| 宽度 800 → 720 | 约 -17% | 该样例640px时小字明显糊 |
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

# 正常速度裁剪：从第3秒取7秒，保留音频（如有）
ffmpeg -ss 3 -t 7 -i in.mp4 -c:v libx264 -crf 20 -c:a aac -movflags +faststart out.mp4

# 只有明确需要加速并静音时使用
ffmpeg -ss 3 -to 10 -i in.mp4 -vf "setpts=PTS/1.5" -an fast-silent.mp4

# 网页友好 MP4
ffmpeg -i in.mov -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -c:a aac -movflags +faststart out.mp4
```

## 成片核验

检查此次交付中的关键动作与结果；无法直接查看视频时抽关键帧，循环素材另比较首尾。UI 小字清晰度及 ffprobe 命令见 [evidence.md](evidence.md#录制尺寸与成片验收)。先保留原片，仅在有体积或格式目标时转码；上面的GIF参数用于体积取舍，不是测试证据的默认规格
