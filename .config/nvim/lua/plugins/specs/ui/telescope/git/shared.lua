local M = {}

function M.yank(text, label)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('Copied ' .. label .. ': ' .. text, vim.log.levels.INFO)
end

function M.open_show_buffer(hash, on_close)
  local lines = vim.fn.systemlist('git show ' .. hash)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'diff'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  vim.cmd('botright split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_set_name(buf, hash:sub(1, 7) .. ' diff')
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      vim.api.nvim_win_close(win, true)
      if on_close then vim.schedule(on_close) end
    end, { buffer = buf, nowait = true })
  end
end

function M.load_vv_git()
  local ok, vvgit = pcall(require, 'vv-git')
  if ok then return vvgit end
  if vim.fn.exists(':VVGitLoad') == 2 then pcall(vim.cmd, 'VVGitLoad') end
  ok, vvgit = pcall(require, 'vv-git')
  return ok and vvgit or nil
end

function M.commit_subject(hash)
  return vim.trim(vim.fn.system('git log -1 --format=%s ' .. hash))
end

return M
