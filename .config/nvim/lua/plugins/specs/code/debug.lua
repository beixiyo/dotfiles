-- DAP debugging with a compact panel and JavaScript, Python, Rust, and Go support
---@type PackSpec
return {
  desc = 'DAP debugger and UI',
  url = 'https://github.com/mfussenegger/nvim-dap',
  main = 'dap',
  dependencies = {
    'https://github.com/igorlfs/nvim-dap-view',
    'https://github.com/microsoft/vscode-js-debug',
    'https://github.com/mfussenegger/nvim-dap-python',
    'https://github.com/leoluz/nvim-dap-go',
    'beixiyo/vv-icons.nvim',
  },

  keys = function()
    local icons = require('vv-icons')
    local d = function(icon, text) return icon .. ' ' .. text end
    local toggle_breakpoint = function()
      local buf = vim.api.nvim_get_current_buf()
      require('dap').toggle_breakpoint()

      -- nvim-dap 会同步更新 sign，主动刷新可让 vv-statuscol 立即显示断点
      require('vv-statuscol').refresh(buf)
    end

    return {
      { '<leader>db', toggle_breakpoint, desc = d(icons.debug_breakpoint, 'Toggle breakpoint') },
      {
        '<leader>dc',
        function() require('config.dap').continue() end,
        desc = d(icons.debug_continue, 'Continue to next breakpoint'),
      },
      { '<leader>dp', function() require('dap').pause() end, desc = d(icons.debug_pause, 'Pause') },
      {
        '<leader>di',
        function() require('dap').step_into() end,
        desc = d(icons.debug_step_into, 'Step into function'),
      },
      {
        '<leader>do',
        function() require('dap').step_over() end,
        desc = d(icons.debug_step_over, 'Step over to next line'),
      },
      {
        '<leader>dO',
        function() require('dap').step_out() end,
        desc = d(icons.debug_step_out, 'Step out of function'),
      },
      {
        '<leader>dr',
        function() require('dap').restart() end,
        desc = d(icons.debug_restart, 'Restart current session'),
      },
      {
        '<leader>dl',
        function() require('dap').run_last() end,
        desc = d(icons.debug_run_last, 'Run last configuration'),
      },
      {
        '<leader>dt',
        function()
          require('dap').terminate({ all = true, hierarchy = true })
          require('dap-view').close(true)
        end,
        desc = d(icons.debug_terminate, 'Terminate all debug sessions'),
      },
      {
        '<leader>dd',
        function() require('dap').disconnect() end,
        desc = d(icons.debug_disconnect, 'Disconnect debugger'),
      },
      { '<leader>du', function() require('dap-view').toggle() end, desc = d(icons.window, 'Toggle debug panel') },
      {
        '<leader>dv',
        function() require('dap-view').virtual_text_toggle() end,
        desc = d(icons.cursor, 'Toggle debug values'),
      },
      {
        '<leader>de',
        function() require('dap-view').hover() end,
        mode = { 'n', 'x' },
        desc = d(icons.code, 'Evaluate'),
      },
    }
  end,

  config = function() require('config.dap').setup() end,
}
