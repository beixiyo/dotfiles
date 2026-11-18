# sysm：PDF、文本与系统能力

```bash
sysm --help
sysm pdf --help
sysm language --help

sysm language detect "This is a local mock document." --json
sysm language tokenize "Alice builds useful local tools." --unit word --json
sysm pdf text "document.pdf" --page 1 --json
sysm pdf thumbnail "document.pdf" --page 1 --size 600 -o preview.png
```

PDF 合并、拆页、旋转、压缩、OCR 文本层等按 `sysm pdf <子命令> --help` 查参数。`pdf text` 只提取文本层，不能据空结果认定扫描 PDF 没内容。Office 转 Markdown 仍优先 anydoc

自然语言包括 detect/tokenize/entities/tag/lemma。PDF、文本任务不需要读取真实应用数据

sysm 还暴露 clipboard、shortcuts、system、calendar、reminders、contacts、notes、mail、photos、finder、network、ai 等领域。仅按用户明确需求进入对应命令，先看子命令帮助：读写与权限差别很大；不要为了探测能力运行所有领域

个人应用读写可能需要 Automation / 隐私权限。Apple Intelligence 依赖系统、硬件、语言及模型可用性；当前只核实命令入口，未进行真实请求。sysm 的天气、网络、Slack 等功能可能访问网络，不能把整个 sysm 笼统称为无网络工具；发送消息仍需明确指令

已验证版本为 sysm 1.26.4.2；来源：[sysm](https://github.com/brndnsvr/sysm)。以实际命令帮助为准
