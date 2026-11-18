---
name: macos-native
description: 需要批量/离线提取、机器可读的检测结果，或实际生成/转换图片、PDF、音视频和 mock 素材时，使用 macOS CLI，按任务选择 sense、auge、sysm、ffmpeg；系统与应用操作按用户请求执行。当前模型能直接查看图片时，普通看图理解、界面分析、图表和复杂版式解读优先直接识图，不强制调用 CLI
---

## 先判断是否需要 CLI

- 当前模型能直接查看图片时，图片描述、界面问题、图表含义、上下文推理、复杂版式/表格理解，优先直接看原图；不要先转成 OCR 文本或分类标签再回答，以免丢失空间关系、颜色和视觉语义
- 需要批量处理、离线执行、可复现的脚本、坐标/掩码/固定标签，或实际产出缩放图、透明 PNG、PDF、音视频文件时，使用下表中的 CLI。这些工具是执行与结构化提取能力，不是模型识图的必经前置步骤
- 结合使用时，以原图保留上下文，OCR 辅助定位/检索；模型判断和工具输出都可能有误。不要把模型补全的字段冒充 OCR 原始结果，也不要假定模型或 CLI 在所有任务上更准确
- 只是读少量文字且当前模型可以直接识别时，无需额外跑 OCR；需要可保存、可检索的转写或大量文件时再使用 OCR

## 按任务选工具

| 用户目标 | 首选 |
|---|---|
| 图片、扫描 PDF 中的文字，位置与置信度，可搜索 PDF | `sense vision ocr`（[视觉与 OCR](references/vision.md)） |
| 分类、人脸/人体/手部/条码检测、抠图、相似图片 | `sense vision`（[视觉与 OCR](references/vision.md)） |
| 需要程序消费的文档结构或特定 Vision 检测结果 | `auge`；结构输出需校验（[视觉与 OCR](references/vision.md)） |
| 图片格式、尺寸、裁切与 mock 图像处理 | `sense vision convert/resize/crop/filter` |
| TTS mock 语音、音频转码、剪辑、分段、音量、STT | `sense audio`（[音视频与 mock](references/media.md)） |
| 视频抽帧、缩略图、OCR、检测、场景与接触表 | `sense vision video`（[音视频与 mock](references/media.md)） |
| 通用视频转码、压缩、容器转换、合成测试视频 | 已安装的 `ffmpeg`（[音视频与 mock](references/media.md)） |
| PDF 合并/拆页/预览/元数据、语言检测/分词/实体 | `sysm pdf`、`sysm language`（[系统与文本](references/system.md)） |
| macOS 系统、内置应用或 Apple Intelligence | `sysm <领域>`（[系统与文本](references/system.md)） |
| Office、EPUB、CSV 等转 Markdown | `anydoc`（`convert-documents-to-markdown` skill） |


## 运行约定

- 初次执行或环境变化时检查 `command -v sense auge sysm` 和各自 `--version`。命令以本机帮助为准，不把三者参数混用：sense 通常 `--json`，auge `--json/-o json`，sysm 由子命令决定
- `sense audio` 用 `<命令> -h`，`sense vision` 和 sysm 用 `<命令> --help`；auge 用 `auge --help`
- 输出写到任务目录的新文件，不覆盖源文件；输入文件路径含空格时引用。JSON 只捕获 stdout，保留 stderr 诊断；图像、音频等二进制流落文件
- 使用 CLI 处理文件时优先本地完成。STT 不添加 `--allow-network`，OCR 不默认启用 auge `--clean`（它调用语言模型重写，不能当原始提取）。缺权限、语言模型或 Apple Intelligence 可用性时报告缺失前提，不自动改成云端
- OCR confidence 不是正确率；表格/多栏/金额/编号要对照原图。工具成功退出不代表结构正确或所有字段齐全
- 生成的语音/测试视频标注为合成 mock。确认文件可解码、尺寸/时长/采样率符合要求；未试听不得声称听感已验证，未实际转录不得声称语音识别已验证

## 本机验证边界

2026-10-23：sense 3.2.1、auge 1.9.0、sysm 1.26.4.2、ffmpeg 8.1。已执行 OCR、二维码、分类、前景抠图、同图相似度、图片缩放、视频抽帧/转码、TTS 文件生成、音频转码、语言检测、分词、PDF 预览。auge 文档请求已执行，但表格字段不完整，限制见视觉参考。STT、相机/屏幕/麦克风采集、个人应用读写、Apple Intelligence 均未在本次验收；不要把“帮助中有命令”表述为“本机已验证”
