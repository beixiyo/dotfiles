-- vv-explorer.nvim — 自实现 VSCode 风文件树
---@type PackSpec
return {
  desc = '自实现 VSCode 风文件树（无 nui/plenary 依赖）',
  url  = 'beixiyo/vv-explorer.nvim',
  main = 'vv-explorer',
  dependencies = { 'beixiyo/vv-utils.nvim', 'beixiyo/vv-icons.nvim' },

  event = 'VimEnter',
  cmd = { 'VVExplorerToggle', 'VVExplorerOpen', 'VVExplorerClose', 'VVExplorerReveal', 'VVExplorerFocus', 'VVExplorerTrash', 'VVExplorerExecute' },
  keys = function()
    local icons = require('vv-icons')
    return {
      { '<leader>e', '<cmd>VVExplorerReveal<cr>', desc = icons.explorer .. ' vv-explorer' },
      { '<leader>E', '<cmd>VVExplorerToggle<cr>', desc = icons.explorer .. ' vv-explorer (toggle)' },
    }
  end,

  ---@type VVExplorerConfig
  opts = {
    -- 图标规则：glob 用 vim.glob.to_lpeg，pattern 用 Lua pattern
    -- 例：
    --   { glob = '**/*.{test,spec}.{ts,tsx,js,jsx}', icon = '', hl = 'NeoTreeFileIcon' },
    --   { pattern = '^README', icon = '', hl = 'Title' },
    --   { glob = '.env*', icon = '', hl = 'WarningMsg' },
    icon_rules = {},
    -- vendor 默认 global_mappings 仍绑 <leader>e/E，但此处 keys 覆盖了 desc，效果一致
    preview = true,

    -- X 执行文件：跑在浮动终端（复用 tools.term，和 t 一致），确认框走 vendor 默认
    execute = {
      run = function(cmd, ctx)
        require('tools.term').run(cmd, ctx.cwd)
      end,
    },

    -- 树内键位覆盖（deep_extend 合并进 vendor 默认 mappings，不影响其余键）
    mappings = {
      -- t：在当前节点目录开/切换浮动终端（目录用自身，文件用父目录），cwd 跟随光标
      ['t'] = function()
        local path = require('vv-explorer').get_node_path()
        if not path then return end

        local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
        require('tools.term').open_at(dir)
      end,

      -- <leader>sg / <leader>ff：以光标节点（或多选节点）为范围启动 fff，目录含全部子孙，文件仅自身
      -- 范围以 glob token 写进 query（可编辑 / <M-p> 调整），不切换 fff 索引根
      ['<leader>sg'] = function()
        require('plugins.specs.tools.fff.scope').live_grep(require('vv-explorer').get_target_paths())
      end,
      ['<leader>ff'] = function()
        require('plugins.specs.tools.fff.scope').find_files(require('vv-explorer').get_target_paths())
      end,
    },
  },
}
