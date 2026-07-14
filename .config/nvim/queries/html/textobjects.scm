; inherit all original plugin patterns + add @tag.outer

(element) @function.outer @tag.outer

(element
  (start_tag)
  .
  (_) @function.inner
  .
  (end_tag))

(attribute_value) @attribute.inner

(attribute) @attribute.outer

(element
  (start_tag)
  _+ @function.inner
  (end_tag))

(script_element) @function.outer @tag.outer

(script_element
  (start_tag)
  .
  (_) @function.inner
  .
  (end_tag))

(style_element) @function.outer @tag.outer

(style_element
  (start_tag)
  .
  (_) @function.inner
  .
  (end_tag))

((element
  (start_tag
    (tag_name) @_tag)) @class.outer
  (#match? @_tag "^(html|section|h[0-9]|header|title|head|body)$"))

((element
  (start_tag
    (tag_name) @_tag)
  .
  (_) @class.inner
  .
  (end_tag))
  (#match? @_tag "^(html|section|h[0-9]|header|title|head|body)$"))

((element
  (start_tag
    (tag_name) @_tag)
  _+ @class.inner
  (end_tag))
  (#match? @_tag "^(html|section|h[0-9]|header|title|head|body)$"))

(comment) @comment.outer

; HTML 属性
(attribute) @property.outer
