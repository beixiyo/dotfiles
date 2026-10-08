-- 定向查看（tools.editor-split）的窗口布局契约：四象限、自定义行列上限、标签保留、
-- 独立视图与工具窗口隔离；每个场景独立 child Neovim 与真实临时文件，不共享窗口标签状态
local H = dofile('tests/helpers.lua')
local T, child = H.new_set({ 'VV_ICONS', 'VV_BUFFERLINE' })

-- 公共前置：编辑器选项 + vv-bufferline（关闭诊断/hover/keys，只测布局）+ 场景辅助函数
-- bar / split / file / scene / wins / other / show 注册为 child 全局，供各场景直接使用
local function boot()
  child.lua([[
    vim.o.hidden = true
    vim.o.splitright = true
    vim.o.splitbelow = true
    vim.o.lines = 60
    vim.o.columns = 180
    bar = require('vv-bufferline')
    bar.setup({ diagnostics = { enabled = false }, hover_close = false, keys = false })
    split = require('tools.editor-split')
    serial = 0

    -- 每个场景使用独立 tab 和真实临时文件
    function file()
      serial = serial + 1
      local path = vim.fn.getcwd() .. '/' .. serial .. '.txt'
      local lines = {}
      for i = 1, 200 do lines[i] = 'line ' .. i end
      vim.fn.writefile(lines, path)
      vim.cmd.edit(path)
      return vim.api.nvim_get_current_buf()
    end

    function scene()
      vim.cmd.tabnew()
      vim.cmd('tabonly!')
      local buf = file()
      return vim.api.nvim_get_current_win(), buf
    end

    function wins()
      return vim.api.nvim_tabpage_list_wins(0)
    end

    function other(source)
      for _, win in ipairs(wins()) do
        if win ~= source then return win end
      end
    end

    function show(axis, limits)
      local source = vim.api.nvim_get_current_win()
      split.show(vim.tbl_extend('force', limits or {}, { axis = axis }))
      eq(vim.api.nvim_get_current_win(), source, '查看另一侧后焦点必须留在原窗口')
    end
  ]])
end

T['重复定向只能形成四象限'] = function()
  boot()
  child.lua_func(function()
    -- 旧映射重复执行会产生第三列／行；新行为无论先上下还是先左右都只能形成四象限
    for _, axis in ipairs({ 'vertical', 'horizontal' }) do
      local cross = axis == 'vertical' and 'horizontal' or 'vertical'
      local source, a = scene()
      show(axis)
      local target = other(source)
      eq(#wins(), 2, '首个按键必须创建对应分屏')
      eq(vim.api.nvim_win_get_buf(target), a, '单文件分屏必须复制显示同一 buffer')
      check(bar.has(source, a) and bar.has(target, a), '复制显示不得移除原窗口标签')
      for _ = 1, 3 do show(axis) end
      eq(#wins(), 2, '重复同方向查看不得创建第三行／列')
      show(cross)
      vim.api.nvim_set_current_win(target)
      show(cross)
      eq(#wins(), 4, '两个方向应允许创建完整 2×2，而不是总数限制为两个')
      for _, win in ipairs(wins()) do
        vim.api.nvim_set_current_win(win)
        show('horizontal')
        show('vertical')
      end
      eq(#wins(), 4, '四象限任意窗口重复操作都不得创建第五个窗口')
    end
  end)
end

T['自定义行列上限真正可达'] = function()
  boot()
  child.lua_func(function()
    -- 更大的非方形上限必须真正可达：两行三列、三行一列均可逐格扩展
    for _, limits in ipairs({ { max_rows = 2, max_columns = 3 }, { max_rows = 3, max_columns = 1 },
      { max_rows = 1, max_columns = 1 } }) do
      local source, a = scene()
      local columns = { source }
      for col = 2, limits.max_columns do
        vim.api.nvim_set_current_win(columns[#columns])
        local before = wins()
        show('vertical', limits)
        for _, win in ipairs(wins()) do
          if not vim.tbl_contains(before, win) then columns[#columns + 1] = win end
        end
        eq(#columns, col, '列上限大于 2 时必须能从最右侧创建下一列')
      end
      for _, top in ipairs(columns) do
        local bottom = top
        for _ = 2, limits.max_rows do
          vim.api.nvim_set_current_win(bottom)
          local before = wins()
          show('horizontal', limits)
          for _, win in ipairs(wins()) do
            if not vim.tbl_contains(before, win) then bottom = win end
          end
        end
      end
      local expected = limits.max_rows * limits.max_columns
      eq(#wins(), expected, '自定义行列容量必须可达，不能仍被硬编码为四窗')
      local grid = wins()
      for _, win in ipairs(grid) do
        vim.api.nvim_set_current_win(win)
        show('horizontal', limits)
        show('vertical', limits)
        eq(vim.api.nvim_win_get_buf(win), a, '扩大网格后仍应复制显示，不移动源文件')
      end
      eq(#wins(), expected, '达到自定义上限后不得再扩展任何一行或一列')

      if limits.max_columns == 3 then
        local left = columns[1]
        vim.api.nvim_set_current_win(columns[2])
        local b = file()
        show('vertical', limits)
        eq(vim.api.nvim_win_get_buf(columns[3]), b, '中间列应优先向右查看')
        eq(vim.api.nvim_win_get_buf(left), a, '向右查看不应覆盖左侧文件')
        vim.api.nvim_set_current_win(columns[3])
        local c = file()
        show('vertical', limits)
        eq(vim.api.nvim_win_get_buf(columns[2]), c, '最右列达到上限后应回看最近的左侧窗口')
      end
    end
  end)
end

T['无效上限明确报错且布局不变'] = function()
  boot()
  child.lua_func(function()
    scene()
    local initial = vim.fn.winlayout()
    local accepted = pcall(split.show, { axis = 'vertical', max_columns = 0 })
    check(not accepted, '无效上限应明确报错，不能静默变成不分屏')
    eq(vim.fn.winlayout(), initial, '配置校验失败不得改变窗口布局')
  end)
end

T['多标签始终复制且保留目标组标签'] = function()
  boot()
  child.lua_func(function()
    local source, c = scene()
    local a = file()
    vim.api.nvim_buf_set_lines(a, 0, 1, false, { 'unsaved edit' })
    show('vertical')
    local target = other(source)
    check(bar.has(source, c) and bar.has(source, a), '多标签分屏也不得移动当前文件')
    eq(vim.api.nvim_win_get_buf(source), a, '原窗口应继续显示 A')
    vim.api.nvim_set_current_win(target)
    local b = file()
    vim.api.nvim_set_current_win(source)
    show('vertical')
    eq(vim.api.nvim_win_get_buf(target), a, '已有 A 标签时应激活 A')
    check(bar.has(target, a) and bar.has(target, b), '切换查看必须保留目标组原有标签')
    check(vim.bo[a].modified, '查看不得写盘或丢弃未保存修改')
    local d = file()
    show('vertical')
    eq(vim.api.nvim_win_get_buf(target), d, '目标没有当前文件时应添加并显示，而不是忽略操作')
    check(bar.has(source, d) and bar.has(target, b), '添加文件不得移动源标签或删除目标旧标签')
  end)
end

T['重复查看同文件保留目标独立视图'] = function()
  boot()
  child.lua_func(function()
    -- 目标已经显示同一 buffer 时，不能重新设置视图而破坏用户上下对照的位置
    local source, a = scene()
    show('vertical')
    local target = other(source)
    vim.api.nvim_win_call(target, function()
      vim.api.nvim_win_set_cursor(target, { 150, 0 })
      vim.cmd('normal! zt')
    end)
    local view = vim.api.nvim_win_call(target, vim.fn.winsaveview)
    show('vertical')
    eq(vim.api.nvim_win_call(target, vim.fn.winsaveview), view, '重复查看同文件必须保留目标独立光标和滚动位置')
    eq(vim.api.nvim_win_get_cursor(source)[1], 1, '目标滚动不应影响源窗口光标')
  end)
end

T['空白编辑窗口被复用'] = function()
  boot()
  child.lua_func(function()
    -- 空白编辑窗口可复用，不能当成无目标而继续分屏
    local source, a = scene()
    vim.cmd.vnew()
    local target = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(source)
    show('vertical')
    eq(#wins(), 2, '空白编辑窗口也应被复用')
    eq(vim.api.nvim_win_get_buf(target), a, '空白目标应显示当前文件')
  end)
end

T['跨整行列候选按上方左方选择'] = function()
  boot()
  child.lua_func(function()
    -- 跨整行／列时两个候选按上方／左方选择，而不是依赖窗口枚举顺序
    for _, axis in ipairs({ 'vertical', 'horizontal' }) do
      local source, a = scene()
      show(axis)
      local target = other(source)
      vim.api.nvim_set_current_win(target)
      local first = file()
      show(axis == 'vertical' and 'horizontal' or 'vertical')
      local lower
      for _, win in ipairs(wins()) do
        if win ~= source and win ~= target then lower = win end
      end
      vim.api.nvim_set_current_win(lower)
      local second = file()
      vim.api.nvim_set_current_win(source)
      show(axis)
      eq(vim.api.nvim_win_get_buf(target), a, '横跨窗口应优先选另一侧上方／左方目标')
      eq(vim.api.nvim_win_get_buf(lower), second, '另一侧下方／右方窗口不应被改动')
      check(bar.has(target, first), '被切换目标的旧文件应仍留在标签组')
    end
  end)
end

T['工具窗口不占分屏额度'] = function()
  boot()
  child.lua_func(function()
    -- 真实固定侧栏、terminal buffer 和浮窗存在时仍允许四个文件窗口，且工具窗口不被覆盖
    local source, a = scene()
    vim.cmd('topleft vnew')
    local sidebar = vim.api.nvim_get_current_win()
    local sidebuf = vim.api.nvim_get_current_buf()
    vim.bo[sidebuf].buftype = 'nofile'
    vim.bo[sidebuf].filetype = 'vv-explorer'
    vim.wo[sidebar].winfixbuf = true
    vim.cmd('vertical resize 24')
    local layout = vim.fn.winlayout()
    show('vertical')
    eq(vim.fn.winlayout(), layout, '从侧边栏触发不能创建分屏')
    vim.api.nvim_set_current_win(source)
    vim.cmd('botright new')
    local terminal = vim.api.nvim_get_current_win()
    local termbuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_open_term(termbuf, {})
    vim.cmd('resize 5')
    vim.api.nvim_set_current_win(source)
    local float = vim.api.nvim_open_win(a, false, { relative = 'editor', row = 0, col = 0, width = 10, height = 2 })
    show('vertical')
    local right
    for _, win in ipairs(wins()) do
      if win ~= source and win ~= sidebar and win ~= terminal and win ~= float then right = win end
    end
    show('horizontal')
    vim.api.nvim_set_current_win(right)
    show('horizontal')
    eq(#wins(), 7, '三个工具窗口不得占用四个文件分屏的额度')
    eq(vim.api.nvim_win_get_buf(sidebar), sidebuf, 'winfixbuf 侧栏必须保持原 buffer')
    eq(vim.api.nvim_win_get_buf(terminal), termbuf, '终端不得被当成文件目标覆盖')
    eq(vim.api.nvim_win_get_buf(float), a, '显示文件的浮窗也不得参与布局')
  end)
end

T['三行布局不扩展不重排'] = function()
  boot()
  child.lua_func(function()
    -- 外部命令已经造出三行时不再扩大无效布局，也不擅自整理既有窗口
    local source = scene()
    vim.cmd.split()
    vim.cmd.split()
    local before = vim.fn.winlayout()
    show('vertical')
    eq(vim.fn.winlayout(), before, '已有三行的布局不得继续扩展或被强行重排')
  end)
end

return T
