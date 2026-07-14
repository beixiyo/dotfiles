-- Test runner UI for Vitest and Jest; nearest tests can reuse nvim-dap
local function discovery_consumer(client)
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then return {} end

  -- 等所有内置 consumers 注册完成，再通过公开 Client API 启动当前文件发现
  vim.schedule(function()
    require('nio').run(function()
      client:get_position(file)
    end)
  end)

  return {}
end

local function register_statuscol_click()
  vim.schedule(function()
    local ok, statuscol = pcall(require, 'vv-statuscol')
    if not ok or not statuscol.on_click then return end

    statuscol.on_click(function(pos)
      if not vim.api.nvim_win_is_valid(pos.winid) then return false end

      local buf = vim.api.nvim_win_get_buf(pos.winid)
      local placed = vim.fn.sign_getplaced(buf, {
        group = 'neotest-status',
        lnum = pos.line,
      })
      local signs = placed[1] and placed[1].signs or {}
      if #signs == 0 then return false end

      vim.api.nvim_win_call(pos.winid, function()
        require('neotest').run.run()
      end)

      return true
    end)
  end)
end

local function is_test_file(path)
  path = path:gsub('\\', '/')
  if not path:match('%.[jt]sx?$') then return false end

  return path:match('%.test%.[jt]sx?$') ~= nil
    or path:match('%.spec%.[jt]sx?$') ~= nil
    or path:find('/__tests__/', 1, true) ~= nil
end

local function register_test_keymaps()
  local function bind(buf)
    if not is_test_file(vim.api.nvim_buf_get_name(buf)) then return end

    vim.keymap.set('n', 'gx', function()
      require('neotest').run.run()
    end, {
      buffer = buf,
      desc = 'Run nearest test',
    })
  end

  local group = vim.api.nvim_create_augroup('NeotestBufferKeymaps', { clear = true })
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(args) bind(args.buf) end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then bind(buf) end
  end
end

---@type PackSpec
return {
  desc = 'Vitest/Jest runner and debugger',
  url = 'https://github.com/nvim-neotest/neotest',
  main = 'neotest',
  dependencies = {
    'https://github.com/nvim-neotest/nvim-nio',
    'https://github.com/nvim-treesitter/nvim-treesitter',
    'https://github.com/marilari88/neotest-vitest',
    'https://github.com/nvim-neotest/neotest-jest',
    'https://github.com/mfussenegger/nvim-dap',
    'https://github.com/igorlfs/nvim-dap-view',
    'beixiyo/vv-icons.nvim',
  },

  event = {
    'BufReadPost *.{test,spec}.{js,jsx,ts,tsx}',
    'BufReadPost */__tests__/*.{js,jsx,ts,tsx}',
    'BufNewFile *.{test,spec}.{js,jsx,ts,tsx}',
    'BufNewFile */__tests__/*.{js,jsx,ts,tsx}',
  },

  keys = function()
    return {
      { '<leader>tn', function() require('neotest').run.run() end,                       desc = 'Run nearest test' },
      { '<leader>tF', function() require('neotest').run.run(vim.fn.expand('%')) end,     desc = 'Run test file' },
      { '<leader>tT', function() require('neotest').run.run(vim.uv.cwd()) end,           desc = 'Run all tests' },
      {
        '<leader>td',
        function()
          -- 与普通调试共享 adapters、断点样式和 dap-view 面板配置
          require('config.dap').setup()
          require('neotest').run.run({ strategy = 'dap' })
        end,
        desc = 'Debug nearest test',
      },
      { '<leader>tx', function() require('neotest').run.stop() end,                      desc = 'Stop test' },
      { '<leader>to', function() require('neotest').output.open({ enter = true }) end,   desc = 'Test output' },
      { '<leader>tu', function() require('neotest').summary.toggle() end,                desc = 'Toggle test summary' },
    }
  end,

  config = function()
    local icons = require('vv-icons')
    local neotest = require('neotest')

    neotest.setup({
      adapters = {
        require('neotest-vitest'),
        require('neotest-jest')({
          jestCommand = function(path)
            -- 从测试文件向上定位项目根，避免 monorepo 误用其他包或全局的 Jest
            local root = vim.fs.root(path, { 'pnpm-lock.yaml', 'bun.lock', 'bun.lockb', 'package-lock.json', 'yarn.lock' })
            return root and (root .. '/node_modules/.bin/jest') or 'jest'
          end,
        }),
      },
      consumers = { file_discovery = discovery_consumer },
      icons = { test = icons.test },
      highlights = {
        namespace = 'NeotestPassed',
        test = 'NeotestPassed',
      },
      output = { open_on_run = false },
      quickfix = { open = false },
      summary = { open = 'botright vsplit | vertical resize 48' },
    })

    register_statuscol_click()
    register_test_keymaps()
  end,
}
