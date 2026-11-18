# 音视频与开发 mock

## TTS、音频转换与转录

```bash
# 写合成语音文件，不播放
sense audio talk --voice en-US -o mock.wav "This is a local mock audio sample."
sense audio info mock.wav --json

# 输出格式由文件扩展名决定；这里重采样为 16k 单声道
sense audio convert mock.wav mock.m4a --rate 16000 --channels 1
sense audio info mock.m4a --json

# 本地文件 STT；尚未在本机验收，不加 --allow-network
sense audio transcribe mock.wav --lang en-US --json
sense audio transcribe mock.wav --lang en-US --srt > mock.srt
```

语音输出检查实际日志中的 voice；`--voice` 匹配不到期望声音时不能假定已使用指定人声。语音模型/声音可能未安装，缺少时说明所需设置，不自动打开安装 UI。STT 可能需要系统授权与本地听写模型。音频 trim/split/gain 的参数先看各自 `-h`；MP3 编码依赖 PATH 中的 lame/ffmpeg

## 视频分析与抽帧

```bash
sense vision video frames mock.mp4 -o 'frame_%03d.jpg' --fps 1
sense vision video thumb --help
sense vision video ocr --help
sense vision video contact --help
```

sense 3.2.1 的 `vision video` 是抽帧与分析工具，没有通用视频转码子命令。此类任务复用本机已有 ffmpeg，不尝试编造 `sense video convert`

```bash
# 2 秒 320×240 的合成测试视频
ffmpeg -hide_banner -loglevel error \
  -f lavfi -i 'testsrc2=size=320x240:rate=10:duration=2' \
  -c:v libx264 -pix_fmt yuv420p mock.mp4

# 常见 MP4 转码/缩放；这里明确去掉音轨
ffmpeg -hide_banner -i input.mov -vf scale=640:-2 \
  -an -c:v libx264 -pix_fmt yuv420p output.mp4

# 解码前检查媒体属性
ffprobe -v error -show_streams -show_format -of json output.mp4
```

ffmpeg 参数应按任务选择，不能默认删掉用户要求保留的音轨；上例 `-an` 仅供无声 mock。现有目标文件时另取名称，不默认加 `-y` 覆盖。复杂编码/兼容性问题按实际 ffmpeg 帮助和官方文档核实

本机已验证合成 WAV、AAC/M4A 转码、2 秒测试视频、缩放转码及抽帧；没有试听、麦克风录音或 STT 质量验证
