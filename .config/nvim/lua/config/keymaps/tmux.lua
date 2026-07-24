local h = require("config.keymaps.helpers")
local map = h.map

require('tools.term').setup_tmux_cwd_sync()

local severity_labels = { 'Error', 'Warn', 'Info', 'Hint' }

local function panel_node_path()
  local ft = vim.bo.filetype
  if ft == 'vv-explorer' then
    return require('vv-explorer').get_node_path()
  elseif ft == 'vv-git-panel' or vim.b.vv_git_scratch then
    -- vv-git-panel = 文件树；vv_git_scratch = diff1 scratch buffer（无 buffer name）
    local s = require('vv-git.state').get()
    if s.cur_path and s.git_root then
      return s.git_root .. '/' .. s.cur_path
    end
  end
end

local function send_path_to_pane(is_visual)
  return function()
    local in_tmux    = vim.env.TMUX ~= nil
    local in_kitty   = vim.env.KITTY_WINDOW_ID ~= nil or vim.env.NVD_KITTY_TARGET_WINDOW ~= nil
    local in_wezterm = vim.env.WEZTERM_PANE ~= nil

    local base_text, diags
    local node_path = panel_node_path()
    if node_path then
      base_text = node_path
      diags     = {}
    else
      local p = vim.fn.expand('%:p')
      if p == '' then return end
      p = require('vv-utils.path').norm(p)

      if is_visual then
        local l1 = vim.fn.line("v")
        local l2 = vim.fn.line(".")
        if l1 > l2 then l1, l2 = l2, l1 end
        p = l1 == l2 and string.format('%s:%d', p, l1) or string.format('%s:%d-%d', p, l1, l2)
      else
        p = p .. ':' .. vim.api.nvim_win_get_cursor(0)[1]
      end

      base_text = p
      diags     = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
    end

    if not in_tmux and not in_kitty and not in_wezterm then
      local clip = base_text
      if #diags > 0 then
        vim.cmd('redraw')
        if vim.fn.confirm('Include diagnostics?', '&Yes\n&No', 2) == 1 then
          for _, d in ipairs(diags) do
            clip = clip .. '\n' .. (severity_labels[d.severity] or 'Unknown') .. ': ' .. d.message
          end
        end
      end
      return require('vv-utils.editor').copy(clip, { title = 'CopyPath' })
    end

    local text = base_text
    for _, d in ipairs(diags) do
      text = text .. '\n' .. (severity_labels[d.severity] or 'Unknown') .. ': ' .. d.message
    end

    local cmd, warn_msg, script
    if in_tmux then
      script   = vim.env.HOME .. "/.config/tmux/scripts/send-to-pane.sh"
      cmd      = script
      warn_msg = "No target tmux pane found"
    elseif in_kitty then
      if vim.fn.executable('bun') == 0 then
        return vim.notify("bun is required but not found in PATH", vim.log.levels.ERROR)
      end
      script   = vim.env.HOME .. "/.config/kitty/scripts/send-to-window.ts"
      cmd      = { 'bun', 'run', script }
      warn_msg = "No target kitty window found (open a non-vim split/tab first)"
    else
      if vim.fn.executable('bun') == 0 then
        return vim.notify("bun is required but not found in PATH", vim.log.levels.ERROR)
      end
      script   = vim.env.HOME .. "/.config/wezterm/scripts/send-to-pane.ts"
      cmd      = { 'bun', 'run', script }
      warn_msg = "No target wezterm pane found (open a non-vim split first)"
    end

    if vim.fn.filereadable(script) == 0 then
      return vim.notify("Script not found: " .. script, vim.log.levels.ERROR)
    end

    vim.fn.system(cmd, ' ' .. text .. ' ')
    if vim.v.shell_error ~= 0 then
      vim.notify(warn_msg, vim.log.levels.WARN)
    end
  end
end

map("n", "<leader>ts", send_path_to_pane(false), { desc = "Send path" })
map("x", "<leader>ts", send_path_to_pane(true), { desc = "Send range" })

-- 终端：tmux 下弹 tmux popup（真 tty），否则退回 toggleterm
-- 放这里而不是 toggleterm 的 spec.keys，是为了让 tmux 路径不必加载该插件
map({ "n", "t" }, "<leader>tt", function()
  require("tools.term").toggle()
end, { desc = "Toggle term" })
