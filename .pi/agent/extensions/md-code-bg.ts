/**
 * Markdown 行内代码背景色块 — opencode 风格
 *
 * pi 主题没有 markdown 元素级背景 token，这里通过官方 registerMarkdownTransformer
 * 在解析前把 `code` 替换为「青前景 + surface0 背景」的 ANSI 串（渲染管线透传）
 * fenced 代码块内容不动（语法高亮管线接管，注入会被覆盖）
 *
 * 依赖 ANSI 透传这一未文档化行为，pi 版本更新后若失效直接删除本文件即可
 */
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent'

/** 底色（pretty-cat surface0 #313244）；前景 mdCode 青 #42b3c2 */
const BG = '\x1b[48;2;49;50;68m'
const FG = '\x1b[38;2;66;179;194m'
const RESET = '\x1b[39m\x1b[49m'

export default function(pi: ExtensionAPI) {
  pi.registerMarkdownTransformer((markdown) =>
    markdown
      .split(/(```[\s\S]*?(?:```|$))/g)
      .map((part, i) =>
        i % 2 === 1
          ? part
          : part.replace(/`([^`\n]+)`/g, (_, code: string) => `${BG}${FG} ${code} ${RESET}`)
      )
      .join('')
  )
}
