; extends
; 常量仅按关键字 const 高亮，不再按全大写命名
; @see nvim-treesitter queries/ecma/highlights.scm 中全大写即 @constant 的规则被下方 priority 覆盖

; 1. 普通的 const 声明
(
  (lexical_declaration
    kind: "const"
    (variable_declarator
      name: (identifier) @constant))
  (#set! "priority" 128)
)

; 2. 修复：解构赋值（数组和对象）中的 const 声明
(
  (lexical_declaration
    kind: "const"
    (variable_declarator
      name: [
        (array_pattern (identifier) @constant)
        (object_pattern (shorthand_property_identifier_pattern) @constant)
        (object_pattern (pair_pattern value: (identifier) @constant))
      ]))
  (#set! "priority" 128)
)

; 全大写标识符改为 @variable，不再当作常量（覆盖 ecma 默认的 @constant）
(
  (identifier) @variable
  (#lua-match? @variable "^_*[A-Z][A-Z%d_]*$")
  (#set! "priority" 127)
)

(
  (shorthand_property_identifier) @variable
  (#lua-match? @variable "^_*[A-Z][A-Z%d_]*$")
  (#set! "priority" 127)
)
