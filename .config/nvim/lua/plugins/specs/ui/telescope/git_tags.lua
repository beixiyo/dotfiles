-- Git tag picker：按创建时间浏览 tag，预览 annotation/commit diff，并接入 vv-git
local M = {}

local function time_fmt(ts)
  if ts <= 0 then return '---- -- --' end
  return os.date('%Y-%m-%d', ts)
end

local function query_tags()
  local lines = vim.fn.systemlist({
    'git', 'for-each-ref',
    '--sort=-creatordate',
    '--format=%(refname:short)%00%(objecttype)%00%(objectname)%00%(*objectname)%00%(creatordate:unix)%00%(subject)%00%(*subject)',
    'refs/tags',
  })

  if vim.v.shell_error ~= 0 then
    vim.notify('Git tags: ' .. vim.trim(table.concat(lines, '\n')), vim.log.levels.ERROR)
    return {}
  end

  local tags = {}
  for _, line in ipairs(lines) do
    -- systemlist 把 NUL 字段分隔符保留为字符串内的 \n；真实记录仍按 list item 隔离
    local fields = vim.split(line, '\n', { plain = true })
    local name, object_type, object_hash, peeled_hash = fields[1], fields[2], fields[3], fields[4]
    if name and name ~= '' and object_hash and object_hash ~= '' then
      local annotated = object_type == 'tag'
      local target_hash = peeled_hash ~= '' and peeled_hash or object_hash
      local tag_subject = fields[6] or ''
      local commit_subject = fields[7] ~= '' and fields[7] or tag_subject
      tags[#tags + 1] = {
        name = name,
        annotated = annotated,
        kind = annotated and 'annotated' or 'lightweight',
        target_hash = target_hash,
        target_short = target_hash:sub(1, 7),
        time = time_fmt(tonumber(fields[5]) or 0),
        subject = commit_subject,
        tag_subject = annotated and tag_subject or '',
      }
    end
  end

  return tags
end

local function yank(text, label)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('Copied ' .. label .. ': ' .. text, vim.log.levels.INFO)
end

local function load_vv_git()
  local ok, vvgit = pcall(require, 'vv-git')
  if ok then return vvgit end

  if vim.fn.exists(':VVGitLoad') == 2 then
    pcall(vim.cmd, 'VVGitLoad')
  end

  ok, vvgit = pcall(require, 'vv-git')
  return ok and vvgit or nil
end

function M.open(opts)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values
  local entry_display = require('telescope.pickers.entry_display')
  local finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  local previewers = require('telescope.previewers')
  opts = opts or {}

  local tags = query_tags()
  if #tags == 0 then
    vim.notify('No Git tags found', vim.log.levels.INFO)
    return
  end

  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = 30 },
      { width = 11 },
      { width = 10 },
      { width = 7 },
      { remaining = true },
    },
  })

  local function make_display(entry)
    return displayer({
      { entry.name, 'TelescopeResultsIdentifier' },
      { entry.kind, entry.annotated and 'Special' or 'Comment' },
      { entry.time, 'Comment' },
      { entry.target_short, 'TelescopeResultsNumber' },
      { entry.subject },
    })
  end

  local function make_entry(tag)
    return {
      value = tag.name,
      ordinal = table.concat({ tag.name, tag.kind, tag.subject, tag.tag_subject }, ' '),
      display = make_display,
      name = tag.name,
      annotated = tag.annotated,
      kind = tag.kind,
      target_hash = tag.target_hash,
      target_short = tag.target_short,
      time = tag.time,
      subject = tag.subject,
      tag_subject = tag.tag_subject,
    }
  end

  local previewer = previewers.new_buffer_previewer({
    title = 'Tag Details',
    define_preview = function(self, entry)
      if self.state.job_id then
        pcall(vim.fn.jobstop, self.state.job_id)
      end

      local bufnr = self.state.bufnr
      local winid = self.state.winid
      local width = vim.api.nvim_win_get_width(winid)
      local chan = vim.api.nvim_open_term(bufnr, {})
      local cmd = 'git show --color=always --decorate=full ' .. vim.fn.shellescape(entry.value)
      if vim.fn.executable('delta') == 1 then
        cmd = cmd .. ' | delta --side-by-side --width=' .. width
      end

      local function send(data)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        local output = vim.tbl_filter(function(line) return line ~= '' end, data or {})
        if #output > 0 then
          vim.api.nvim_chan_send(chan, table.concat(output, '\r\n') .. '\r\n')
        end
      end

      self.state.job_id = vim.fn.jobstart({ 'bash', '-c', cmd }, {
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data) send(data) end,
        on_stderr = function(_, data) send(data) end,
        on_exit = function()
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then return end
            pcall(function()
              vim.bo[bufnr].scrollback = 9999
              vim.bo[bufnr].scrollback = 9998
            end)
            if vim.api.nvim_win_is_valid(winid) then
              pcall(vim.api.nvim_win_set_cursor, winid, { 1, 0 })
            end
          end)
        end,
      })
    end,
  })

  local function open_in_vv_git(prompt_bufnr, method)
    local entry = action_state.get_selected_entry(prompt_bufnr)
    if not entry then return end

    local vvgit = load_vv_git()
    if not vvgit or type(vvgit[method]) ~= 'function' then
      vim.notify('vv-git does not support ' .. method, vim.log.levels.ERROR)
      return
    end

    actions.close(prompt_bufnr)
    vvgit[method](entry.value, function() require('telescope.builtin').resume() end)
  end

  pickers.new(opts, {
    prompt_title = 'CR:diff  H:HEAD  M-h:hash  M-y:tag',
    finder = finders.new_table({
      results = tags,
      entry_maker = make_entry,
    }),
    previewer = previewer,
    sorter = conf.generic_sorter(opts),
    layout_config = { preview_width = 0.7 },

    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        open_in_vv_git(prompt_bufnr, 'show_commit')
      end)

      map('n', 'H', function()
        open_in_vv_git(prompt_bufnr, 'compare_with_head')
      end)

      map({ 'i', 'n' }, '<M-h>', function()
        local entry = action_state.get_selected_entry(prompt_bufnr)
        if entry then yank(entry.target_hash, 'commit hash') end
      end)

      map({ 'i', 'n' }, '<M-y>', function()
        local entry = action_state.get_selected_entry(prompt_bufnr)
        if entry then yank(entry.value, 'tag') end
      end)

      return true
    end,
  }):find()
end

return M
