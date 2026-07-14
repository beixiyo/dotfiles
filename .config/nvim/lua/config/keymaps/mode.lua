local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map("i", "jk", "<Esc>", { desc = icons.exit_insert .. " " .. "Exit insert mode" })

-- 连续 Insert 默认只有一个 undo block；在空格、ASCII 标点和常用中文标点后拆分
local undo_separators = { "<Space>" }

for _, range in ipairs({ { 33, 47 }, { 58, 64 }, { 91, 96 }, { 123, 126 } }) do
  for code = range[1], range[2] do
    undo_separators[#undo_separators + 1] = string.char(code)
  end
end

vim.list_extend(undo_separators, {
  "，", "。", "！", "？", "；", "：", "、", "…", "—", "–", "·", "￥",
  "“", "”", "‘", "’", "「", "」", "『", "』",
  "（", "）", "【", "】", "〔", "〕", "［", "］", "｛", "｝", "〈", "〉", "《", "》",
  "＂", "＃", "＄", "％", "＆", "＇", "＊", "＋", "－", "．", "／",
  "＜", "＝", "＞", "＠", "＼", "＾", "＿", "｀", "｜", "～",
})

for _, separator in ipairs(undo_separators) do
  local existing = vim.fn.maparg(separator, "i", false, true)
  if existing.desc ~= "Pair with undo break" then
    map("i", separator, separator .. "<C-g>u", { desc = "Undo break" })
  end
end
