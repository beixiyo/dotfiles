-- 文件类型特定设置

local function augroup(name)
  return vim.api.nvim_create_augroup("my_nvim_" .. name, { clear = true })
end

vim.filetype.add({
  extension = {
    jsonl = "json",
    ndjson = "json",
  },
})

-- 快速关闭特定文件类型（q / Esc）
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = {
    "PlenaryTestPopup",
    "checkhealth",
    "dbout",
    "gitsigns-blame",
    "help",
    "lspinfo",
    "man",
    "mason",
    "neotest-output",
    "neotest-output-panel",
    "neotest-summary",
    "notify",
    "qf",
    "spectre_panel",
    "startuptime",
    "tsplayground",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(event.buf) then return end
      for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
          vim.cmd("close")
          pcall(vim.api.nvim_buf_delete, event.buf, { force = true })
        end, {
          buffer = event.buf,
          silent = true,
          desc = "Close window",
        })
      end
    end)
  end,
})

-- 文本 / 提交信息启用自动换行与拼写检查
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("wrap_spell"),
  pattern = { "text", "plaintex", "typst", "gitcommit" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

-- JSON 不隐藏引号
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("json_conceal"),
  pattern = { "json", "jsonc", "json5" },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})

-- Markdown：<leader>mp 用 leaf TUI 在浮动窗口里渲染查看
-- 用途：render-markdown 在宽表上会崩（nvim soft-wrap+conceal 限制），改用 leaf TUI 看
-- 渲染「当前 buffer 内容」（含未保存改动）：写临时 .md 再交给 leaf
--
-- 打开方式按环境自动选（终端无关，WezTerm/Kitty/Ghostty + SSH 都可用）：
--   1. 在 tmux 内  → tmux display-popup（首选：跟外层终端/SSH 全无关，需 tmux ≥ 3.2）
--   2. 裸 kitty    → kitten @ launch overlay（开了 remote control 时）
--   3. 其它兜底    → nvim 内置浮窗终端（体验一般但总能用）
-- 依赖 leaf：Arch `yay -S leaf-markdown-viewer`；其它平台 `curl -fsSL …/install.sh | sh`

-- 没装 leaf 时按当前可用的包管理器给出安装提示
-- @link https://leaf.rivolink.mg/#install
local function leaf_install_hint()
  if vim.fn.executable("paru") == 1 then return "paru -S leaf-markdown-viewer" end
  if vim.fn.executable("yay") == 1 then return "yay -S leaf-markdown-viewer" end
  if vim.fn.executable("pacman") == 1 then return "paru/yay -S leaf-markdown-viewer (AUR)" end
  if vim.fn.executable("brew") == 1 then
    return "curl -fsSL https://raw.githubusercontent.com/RivoLink/leaf/main/scripts/install.sh | sh"
  end
  return "见 https://github.com/RivoLink/leaf#installation"
end

local function leaf_preview(buf)
  if vim.fn.executable("leaf") == 0 then
    vim.notify("leaf not installed, install with: " .. leaf_install_hint(), vim.log.levels.WARN)
    return
  end

  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmp)
  local run = "leaf " .. vim.fn.shellescape(tmp)

  -- ① tmux popup：终端无关、SSH 安全
  if vim.env.TMUX and vim.env.TMUX ~= "" then
    vim.system({ "tmux", "display-popup", "-E", "-w", "90%", "-h", "90%", run })
    return
  end

  -- ② 裸 kitty overlay（没用 tmux、但在 kitty 内且开了 remote control）
  local sock = vim.env.KITTY_LISTEN_ON
  if sock and sock ~= "" and vim.fn.executable("kitten") == 1 then
    vim.system({ "kitten", "@", "--to", sock, "launch", "--type=overlay", "--title", "md-preview", "leaf", tmp })
    return
  end

  -- ③ 兜底：nvim 内置浮窗终端
  require("tools.term").run({ "leaf", tmp })
end

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("markdown_leaf_preview"),
  pattern = { "markdown" },
  callback = function(event)
    vim.keymap.set("n", "<leader>mp", function() leaf_preview(event.buf) end, {
      buffer = event.buf,
      silent = true,
      desc = "Preview Markdown",
    })
  end,
})
