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
-- Ctrl+E 通过 RPC 定位原 buffer 并关闭预览，q 可直接退出预览
--
-- 打开方式按环境自动选（终端无关，WezTerm/Kitty/Ghostty + SSH 都可用）：
--   1. 在 tmux 内  → tmux display-popup（首选：跟外层终端/SSH 全无关，需 tmux ≥ 3.2）
--   2. 裸 kitty    → kitten @ launch overlay（开了 remote control 时）
--   3. 其它兜底    → nvim 内置浮窗终端（体验一般但总能用）
-- 依赖 leaf：Arch `yay -S leaf-markdown-viewer-bin`；其它平台 `curl -fsSL …/install.sh | sh`
-- 也可通过 npm 安装：`npm install -g @rivolink/leaf`

-- 没装 leaf 时按当前可用的包管理器给出安装提示
-- @link https://leaf.rivolink.mg/#install
local function leaf_install_hint()
  if vim.fn.executable("paru") == 1 then return "paru -S leaf-markdown-viewer-bin" end
  if vim.fn.executable("yay") == 1 then return "yay -S leaf-markdown-viewer-bin" end
  if vim.fn.executable("pacman") == 1 then return "paru/yay -S leaf-markdown-viewer-bin" end
  if vim.fn.executable("brew") == 1 then
    return "curl -fsSL https://raw.githubusercontent.com/RivoLink/leaf/main/scripts/install.sh | sh"
  end
  if vim.fn.executable("npm") == 1 then return "npm install -g @rivolink/leaf" end
  return "see https://github.com/RivoLink/leaf#installation"
end

-- 预览窗口占终端窗口的比例（宽高相同）
local MARKDOWN_PREVIEW_SCALE = 0.95

local function leaf_preview(buf)
  if vim.fn.executable("leaf") == 0 then
    vim.notify("leaf not installed, install with: " .. leaf_install_hint(), vim.log.levels.WARN)
    return
  end

  local source_win = vim.api.nvim_get_current_win()
  local server = vim.v.servername
  if server == "" then server = vim.fn.serverstart() end

  local tmp = vim.fn.tempname() .. ".md"
  local ok, err = pcall(vim.fn.writefile, vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmp)

  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
    return
  end

  local sessions = require("tools.leaf-preview")
  local id = vim.fn.sha256(tmp):sub(1, 16)
  local function cleanup()
    sessions.remove(id)
    vim.fn.delete(tmp)
  end

  local function on_exit()
    vim.schedule(cleanup)
  end

  -- RPC helper 的父进程就是调用它的 leaf；只退出这个进程，不关闭 client 的其它窗口
  sessions.register(id, { buf = buf, win = source_win, close = function(pid)
    cleanup()
    local ok, err = vim.uv.kill(pid, "sigterm")
    if not ok then vim.notify("Cannot close leaf preview: " .. tostring(err), vim.log.levels.ERROR) end
  end })

  local helper = vim.fn.stdpath("config") .. "/scripts/leaf-editor.lua"
  local editor = ('"%s" --headless -l "%s" "%s" %s {$line}'):format(vim.v.progpath, helper, server, id)

  -- 清除 leaf 的新终端 tab 检测，使 RPC helper 在当前预览里运行
  local script = 'trap \'rm -f -- "$1"; "$3" --headless -l "$4" "$5" "$6" closed\' EXIT; unset KITTY_PID GNOME_TERMINAL_SCREEN WT_SESSION TERM_PROGRAM; leaf --editor "$2" "$1"'
  local argv = { "sh", "-c", script, "md-preview", tmp, editor, vim.v.progpath, helper, server, id }
  local run = table.concat(vim.tbl_map(vim.fn.shellescape, argv), " ")

  -- ① tmux popup：终端无关、SSH 安全
  if vim.env.TMUX and vim.env.TMUX ~= "" then
    local size = math.floor(MARKDOWN_PREVIEW_SCALE * 100) .. "%"
    local query = { "tmux", "display-message", "-p" }
    if vim.env.TMUX_PANE and vim.env.TMUX_PANE ~= "" then
      vim.list_extend(query, { "-t", vim.env.TMUX_PANE })
    end

    query[#query + 1] = "#{client_name}"
    local client = vim.system(query, { text = true }):wait()
    local target = vim.trim(client.stdout or "")

    if client.code ~= 0 or target == "" then
      cleanup()
      vim.notify("Cannot identify tmux preview client", vim.log.levels.ERROR)
      return
    end

    -- 新版 tmux 用 -c 指定 client，旧版用 -t；按实际命令能力选择
    local commands = vim.system({ "tmux", "list-commands" }, { text = true }):wait()
    local popup_spec = (commands.stdout or ""):match("display%-popup[^\n]*") or ""
    local target_flag = popup_spec:find("-c target-client", 1, true) and "-c" or "-t"
    vim.system({ "tmux", "display-popup", target_flag, target, "-E", "-w", size, "-h", size, run }, {}, on_exit)

    return
  end

  -- ② 裸 kitty overlay（没用 tmux、但在 kitty 内且开了 remote control）
  local sock = vim.env.KITTY_LISTEN_ON
  if sock and sock ~= "" and vim.fn.executable("kitten") == 1 then
    local launch = { "kitten", "@", "--to", sock, "launch", "--type=overlay", "--env", "LEAF_PREVIEW_ID=" .. id }

    if vim.env.KITTY_WINDOW_ID and vim.env.KITTY_WINDOW_ID ~= "" then
      vim.list_extend(launch, { "--match", "id:" .. vim.env.KITTY_WINDOW_ID })
    end

    vim.list_extend(launch, { "--title", "md-preview" })
    vim.list_extend(launch, argv)
    vim.system(launch, {}, function(result)
      if result.code ~= 0 then on_exit() end
    end)
    return
  end

  -- ③ 兜底：nvim 内置浮窗终端
  local opened = require("tools.term").run(argv, nil, {
    close_on_exit = true,
    float_opts = {
      width = function() return math.floor(vim.o.columns * MARKDOWN_PREVIEW_SCALE) end,
      height = function() return math.floor(vim.o.lines * MARKDOWN_PREVIEW_SCALE) end,
    },
  })
  if not opened then cleanup() end
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
