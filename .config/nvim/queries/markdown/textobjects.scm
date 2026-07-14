(atx_heading
  heading_content: (_) @class.inner) @class.outer @tag.outer

(setext_heading
  heading_content: (_) @class.inner) @class.outer @tag.outer

(thematic_break) @class.outer

(fenced_code_block
  (code_fence_content) @block.inner) @block.outer

[
  (paragraph)
  (list)
] @block.outer
