# 视觉与 OCR

## OCR 输出格式怎么选

`sense vision ocr` 默认输出纯文本，适合阅读、摘要、搜索和只需要文字的后续处理；普通转写优先保留这个默认。添加 `--json` 才输出 JSON，适合需要坐标、置信度、备选候选、页信息或程序消费的任务

## 常用文件路径（已核实命令）

```bash
# 默认纯文本：普通阅读/转写
sense vision ocr "image.png" --lang en-US > ocr.txt
sense vision ocr "image.png" --lang zh-Hans en-US > ocr.txt

# 需要位置、置信度或候选时才输出 JSON
sense vision ocr "image.png" --lang en-US --json > ocr.json

# 序列号等可关闭语言纠错，不保证提高准确率
sense vision ocr "image.png" --lang en-US --no-correction

# -o 是可搜索 PDF，不是保存提取文字
sense vision ocr "scan.pdf" --pages 1-3 > ocr.txt
sense vision ocr "scan.pdf" -o searchable.pdf

sense vision classify "photo.jpg" --top 5 --json
sense vision detect "image.png" --what barcodes --json
sense vision detect "photo.jpg" --what faces pose hands --json
sense vision segment "photo.jpg" -o cutout.png --json
sense vision segment "photo.jpg" --mask -o mask.png
sense vision similar "a.png" "b.png" --json
sense vision resize "input.png" resized.png --width 550
sense vision convert "input.png" output.jpg
```

`--lang` 接收空格分隔语言列表，不是 sysm 或 auge 的语法。sense JSON 的 OCR 结果是页/输入对象数组，每项含 `lines`、`width`、`height`；位置 `bbox` 为左上原点的像素 `{x,y,w,h}`。旧 Swift OCR 的 JSON 是左下原点的归一化坐标，不可直接复用坐标代码。其他检测器的 schema 也要按实际输出读取

输出文本到文件使用 stdout 重定向；`sense vision ocr -o text.txt` 不会按扩展名输出文本。`--annotate annotated.png` 可导出识别框供复核。`--roi` 为像素矩形，其他 CLI 的 ROI 未必同单位

## auge 的补充路径

```bash
auge --document "scan.png" --json > document.json
auge --ocr "image.png" --langs zh-Hans,en-US --with-boxes --json
auge --hand-pose "photo.jpg" --json
auge --animal-pose "photo.jpg" --json
auge --smudge "photo.jpg" --json
```

只需要一个任务时不运行 `--all`。auge 的 `-o` 是输出格式，不是目标文件路径

**已发现的限制**：本机 auge 1.9.0 对清晰 4×3 表格返回了全部正文，但 `results.document.tables` 中对象的 `row_count=0`、`column_count=0`、`cells=[]`。因此检查行列数、单元格和金额关联；对象存在或退出 0 都不能证明表格解析成功。失败时保留原图，用普通 OCR 加人工/视觉复核；不要把扁平文字自行补成“真实提取”的单元格

文档结构请求已接入不代表所有图都能恢复表格。姿态、抠图也只识别模型能检测的目标；无结果应按无结果报告

来源：[sense](https://github.com/wkoszek/sense)、[auge](https://github.com/Arthur-Ficial/auge)。以安装版本的实际帮助为准
