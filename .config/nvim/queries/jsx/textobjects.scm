; inherits: ecma

(jsx_attribute) @attribute.outer

(jsx_attribute
  (property_identifier)
  (_
    (_) @attribute.inner))

(jsx_element) @call.outer @tag.outer
(jsx_self_closing_element) @call.outer @tag.outer

(jsx_element
  (jsx_opening_element
    (identifier) @call.inner)
  (jsx_closing_element))

(jsx_self_closing_element
  (identifier) @call.inner)
