-- fff grep 列表 renderer：在上游 grep_renderer 基础上只裁掉匹配行的前导缩进（显示层）
-- 不用 fff 的 grep.trim_whitespace：它在 Rust 侧把 item.col 一并左移，而 col 同时用于
-- `:行:列` 显示与确认后的光标跳转，开启后光标会落在偏左一个缩进宽度的位置
-- 这里只改 line_content 与 match_ranges（二者仅被 grep_renderer 读取），col 保持原值
-- 通过 live_grep({ renderer = ... }) 公开参数注入，resume 时 fff 会连同 renderer 一起恢复
local Upstream = require('fff.picker_ui.grep_renderer')

---@param item table fff grep match item
local function trim_indent(item)
  -- 同一 item 会被多次渲染（滚动 / 光标重绘），只裁一次，避免 match_ranges 重复左移
  if item._indent_trimmed or item.is_binary_content or type(item.line_content) ~= 'string' then return end
  item._indent_trimmed = true

  local width = #item.line_content:match('^%s*')
  if width == 0 then return end

  item.line_content = item.line_content:sub(width + 1)
  for _, range in ipairs(item.match_ranges or {}) do
    range[1] = math.max(0, (range[1] or 0) - width)
    range[2] = math.max(0, (range[2] or 0) - width)
  end
end

-- 普通表而非元表继承：main.live_grep 用 tbl_deep_extend 合并 renderer，只会拷贝自有字段
return vim.tbl_extend('force', {}, Upstream, {
  render_line = function(item, ctx, item_idx)
    trim_indent(item)
    return Upstream.render_line(item, ctx, item_idx)
  end,
})
