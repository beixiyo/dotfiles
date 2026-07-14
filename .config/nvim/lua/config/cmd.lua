-- ================================
-- 用户命令（:Foo 形式）集中注册
-- 与 keymaps（按键映射）/ autocmd（事件触发）职责分离
-- ================================

-- sudo 补刀：:W → 提权写入
-- Neovim 的 :w !cmd 走 pipe 无 PTY（neovim/neovim#1716），密码提示不出来
-- 解法：inputsecret() 取密码 → sudo -S（从 stdin 读密码）→ cp tempfile target
local function sudo_write()
  local path = vim.fn.expand('%:p')
  if path == '' then
    vim.notify('W: 文件名为空', vim.log.levels.ERROR)
    return
  end

  local tmp = vim.fn.tempname()
  local ok, err = pcall(vim.cmd, 'write! ' .. vim.fn.fnameescape(tmp))
  if not ok then
    vim.fn.delete(tmp)
    vim.notify('W: 写临时文件失败：' .. tostring(err), vim.log.levels.ERROR)
    return
  end

  local password = vim.fn.inputsecret('[sudo] password: ')
  vim.cmd('redraw')

  -- sudo -S 从 stdin 读密码；cp 不读 stdin，两者无干扰
  vim.fn.system(
    string.format('sudo -S cp %s %s', vim.fn.shellescape(tmp), vim.fn.shellescape(path)),
    password .. '\n'
  )
  vim.fn.delete(tmp)

  if vim.v.shell_error == 0 then
    vim.bo.modified = false
  else
    vim.notify('W: sudo 写入失败', vim.log.levels.ERROR)
  end
end

vim.api.nvim_create_user_command('W', sudo_write, { desc = 'sudo 写入当前文件' })


-- =======================
-- CopyPathLine：复制当前文件绝对路径 + 行号（与 lualine 行号段点击效果一致）
-- normal: path:42  /  visual (`:'<,'>CopyPathLine`): path:42-51
-- =======================
vim.api.nvim_create_user_command("CopyPathLine", function(opts)
  local line_arg
  if opts.range == 2 then
    line_arg = { opts.line1, opts.line2 }
  elseif opts.range == 1 then
    line_arg = { opts.line1, opts.line1 }
  else
    line_arg = true
  end

  local editor = require("vv-utils.editor")
  local p = editor.build_path({ line = line_arg })
  if not p then return end

  local diags = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
  if #diags > 0 then
    vim.cmd('redraw')
    if vim.fn.confirm('Include diagnostics?', '&Yes\n&No', 2) == 1 then
      local labels = { 'Error', 'Warn', 'Info', 'Hint' }
      for _, d in ipairs(diags) do
        p = p .. '\n' .. (labels[d.severity] or 'Unknown') .. ': ' .. d.message
      end
    end
  end

  editor.copy(p, { title = 'CopyPath' })
end, { range = true, desc = "复制当前文件路径 + 行号" })


-- =======================
-- LspInfo：显示当前 buffer 的 LSP 客户端信息（带高亮）
-- =======================
vim.api.nvim_create_user_command("LspInfo", function()
  local hl_mod = require("vv-utils.hl")
  local ns = vim.api.nvim_create_namespace("lsp_info_panel")

  hl_mod.register("lsp_info_panel.hl", {
    LspInfoTitle    = { link = "Title" },
    LspInfoName     = { fg = "#7dcfff", bold = true },
    LspInfoLabel    = { link = "Comment" },
    LspInfoValue    = { link = "Normal" },
    LspInfoVersion  = { fg = "#9ece6a" },
    LspInfoCap      = { fg = "#9ece6a" },
    LspInfoCapOff   = { fg = "#565f89" },
    LspInfoSep      = { fg = "#3b4261" },
    LspInfoEmpty    = { fg = "#565f89", italic = true },
  })

  ---@type {text: string, hls?: {col_start: integer, col_end: integer, group: string}[]}[]
  local rows = {}

  ---@param text string
  ---@param hls? {col_start: integer, col_end: integer, group: string}[]
  local function add(text, hls)
    table.insert(rows, { text = text, hls = hls })
  end

  local function add_plain(text)
    add(text)
  end

  ---@param label string
  ---@param value string
  ---@param value_hl? string
  local function add_field(label, value, value_hl)
    local prefix = "  " .. label .. "  "
    add(prefix .. value, {
      { col_start = 0, col_end = #prefix, group = "LspInfoLabel" },
      { col_start = #prefix, col_end = #prefix + #value, group = value_hl or "LspInfoValue" },
    })
  end

  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local ft = vim.bo.filetype
  local header = ft ~= "" and ("LSP  ·  " .. ft) or "LSP"
  add(header, {
    { col_start = 0, col_end = #header, group = "LspInfoTitle" },
  })

  if #clients == 0 then
    add("")
    local empty = "  No active clients"
    add(empty, {
      { col_start = 0, col_end = #empty, group = "LspInfoEmpty" },
    })
  end

  local cap_labels = {
    { method = "textDocument/completion",     short = "completion" },
    { method = "textDocument/hover",          short = "hover" },
    { method = "textDocument/definition",     short = "definition" },
    { method = "textDocument/references",     short = "references" },
    { method = "textDocument/rename",         short = "rename" },
    { method = "textDocument/codeAction",     short = "codeAction" },
    { method = "textDocument/formatting",     short = "format" },
    { method = "textDocument/signatureHelp",  short = "signature" },
    { method = "textDocument/codeLens",       short = "codeLens" },
    { method = "textDocument/semanticTokens", short = "semanticTokens" },
    { method = "textDocument/inlayHint",      short = "inlayHint" },
  }

  for i, c in ipairs(clients) do
    local sep = string.rep("─", 44)
    add(sep, { { col_start = 0, col_end = #sep, group = "LspInfoSep" } })

    local version = ""
    if c.server_info and c.server_info.version then
      version = "  v" .. c.server_info.version
    end
    local name_line = "  " .. c.name
    add(name_line .. version, {
      { col_start = 0, col_end = #name_line, group = "LspInfoName" },
      { col_start = #name_line, col_end = #name_line + #version, group = "LspInfoVersion" },
    })

    add_plain("")

    local cmd_str = type(c.config.cmd) == "table" and table.concat(c.config.cmd, " ")
      or type(c.config.cmd) == "function" and "<function>"
      or tostring(c.config.cmd)
    add_field("cmd", cmd_str)
    add_field("root", c.root_dir or c.config.root_dir or "—")

    local fts = c.config.filetypes or {}
    add_field("ft", #fts > 0 and table.concat(fts, ", ") or "—")
    add_field("id", tostring(c.id))

    add_plain("")

    -- 能力指示器
    local cap_parts = {}
    local cap_hls = {}
    local prefix = "  "
    local offset = #prefix

    for j, cap in ipairs(cap_labels) do
      local supported = c:supports_method(cap.method, { bufnr = 0 })
      local icon = supported and "●" or "○"
      local label = icon .. " " .. cap.short
      local hl_group = supported and "LspInfoCap" or "LspInfoCapOff"

      table.insert(cap_parts, label)
      table.insert(cap_hls, { col_start = offset, col_end = offset + #label, group = hl_group })
      offset = offset + #label

      if j < #cap_labels then
        local sep_str = "  "
        table.insert(cap_parts, sep_str)
        offset = offset + #sep_str
      end
    end

    -- 按宽度折行
    local max_width = 68
    local line_parts, line_hls = {}, {}
    local cur_offset = #prefix

    for j, cap in ipairs(cap_labels) do
      local supported = c:supports_method(cap.method, { bufnr = 0 })
      local icon = supported and "●" or "○"
      local label = icon .. " " .. cap.short
      local hl_group = supported and "LspInfoCap" or "LspInfoCapOff"
      local sep_str = j < #cap_labels and "  " or ""
      local needed = #label + #sep_str

      if cur_offset + needed > max_width and #line_parts > 0 then
        local line = prefix .. table.concat(line_parts, "")
        add(line, line_hls)
        line_parts, line_hls = {}, {}
        cur_offset = #prefix
      end

      table.insert(line_hls, { col_start = cur_offset, col_end = cur_offset + #label, group = hl_group })
      table.insert(line_parts, label .. sep_str)
      cur_offset = cur_offset + needed
    end

    if #line_parts > 0 then
      add(prefix .. table.concat(line_parts, ""), line_hls)
    end

    if i < #clients then
      add_plain("")
    end
  end

  -- 渲染
  local lines = {}
  for _, r in ipairs(rows) do
    table.insert(lines, r.text)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  for i, r in ipairs(rows) do
    if r.hls then
      for _, h in ipairs(r.hls) do
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, h.col_start, { end_col = h.col_end, hl_group = h.group })
      end
    end
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(72, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " LspInfo ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end, { desc = "显示当前 buffer 的 LSP 客户端信息" })
