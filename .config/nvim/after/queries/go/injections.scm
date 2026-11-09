; extends
; 高亮 struct tag 内部的 key 与 value
; tree-sitter-go 把整个 tag 解析为 raw_string_literal，内部无子节点，纯 query 无法切分
; 将 tag 内容按 Go 语法注入解析（injection.self）：key 落到 @label，字符串值落到 @string
(field_declaration
  tag: (raw_string_literal
    (raw_string_literal_content) @injection.content
    (#set! injection.self)))
