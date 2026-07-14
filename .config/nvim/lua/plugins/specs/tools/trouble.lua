-- 诊断 / LSP 引用列表（按文件分组，类似 VSCode）

-- 文档符号树的「显示局部变量」开关（默认隐藏函数内局部变量噪音）
-- 被 doc_symbols 的 filter 与 H 键共享：H 翻转它再 refresh，filter 据此决定是否隐藏
local symbols_state = { show_locals = false }

---@type PackSpec
return {
  desc = 'LSP/诊断列表（按文件分组）',
  url = 'https://github.com/folke/trouble.nvim',
  main = 'trouble',
  dependencies = { 'https://github.com/nvim-tree/nvim-web-devicons' },

  cmd = { 'Trouble' },
  event = { 'UIEnter' },

  config = function(_, opts)
    require('trouble').setup(opts)

    -- 拦截所有 quickfix 窗口，自动替换为 Trouble（覆盖 fff / vimgrep / grep 等）
    vim.api.nvim_create_autocmd('BufWinEnter', {
      group = vim.api.nvim_create_augroup('TroubleQfReplace', {}),
      callback = function()
        if vim.bo.buftype == 'quickfix' then
          vim.schedule(function() vim.cmd('cclose') vim.cmd('Trouble qflist open') end)
        end
      end,
    })

    -- pretty_dark(本地 fork) 的 CursorLine(#23262c=bg_highlight) 是低饱和冷灰，叠在面板底色
    -- (NormalFloat #141311) 上色相/亮度都太接近，跟随高亮像「同一片黑」看不清。
    -- 换成蓝调的 Visual(#213246) 一拉开色相就跳出来。按 hl 组名引用、不动全局、换主题自动适配。
    -- 想换风格改这里：Visual(蓝,当前) / PmenuSel(#3f4653 浅冷灰) / TabLineSel(#4aa5f0 亮蓝)
    local CURSORLINE_HL = 'Visual'
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'trouble',
      group = vim.api.nvim_create_augroup('TroubleCursorLineHL', {}),
      callback = function(ev)
        vim.schedule(function()
          local win = vim.fn.bufwinid(ev.buf)
          if win == -1 or not vim.api.nvim_win_is_valid(win) then return end
          local wh = vim.wo[win].winhighlight
          if not wh:find('CursorLine:') then
            vim.wo[win].winhighlight = (wh == '' and '' or wh .. ',') .. 'CursorLine:' .. CURSORLINE_HL
          end
        end)
      end,
    })

    -- 预览高亮「穿透」render-markdown：符号树聚焦某符号时，trouble 在源文件上打两个 extmark——
    -- 整行 CursorLine(priority 150) + 符号范围 TroublePreview(priority 160)。但 render-markdown
    -- 的标题底色是 priority 4096 的整行 bg，把这两个底色都盖住了，markdown 下根本看不出选中的是谁。
    --
    -- nvim 对重叠 extmark 是「按属性合并、冲突取高 priority」：底色之争 render-markdown 必赢，
    -- 但 bold / underline 这类它没设的属性会照常透出来。故把 TroublePreview 改成
    -- bold + 下划线(醒目色)：代码文件里照旧能看到 Visual 底色；markdown 里底色虽被盖，
    -- 标题文字仍会加粗 + 描下划线，一眼定位。（trouble 用 default=true 链接，显式覆盖永久生效）
    local function set_preview_hl()
      local visual = vim.api.nvim_get_hl(0, { name = 'Visual', link = false })
      -- 下划线色用 DiagnosticWarn 前景(多为暖黄/橙)，跟 markdown 标题的冷蓝底色对比强；取不到则兜底亮黄
      local warn = vim.api.nvim_get_hl(0, { name = 'DiagnosticWarn', link = false })
      vim.api.nvim_set_hl(0, 'TroublePreview', {
        bg = visual and visual.bg or nil,
        bold = true,
        underline = true,
        sp = (warn and warn.fg) or '#ffcc00',
      })
    end

    set_preview_hl()
    -- 换主题会清空高亮，重设一次（trouble 自己的 ColorScheme 钩子不重链 TroublePreview，互不干扰）
    vim.api.nvim_create_autocmd('ColorScheme', {
      group = vim.api.nvim_create_augroup('TroublePreviewHL', {}),
      callback = set_preview_hl,
    })
  end,

  ---@type trouble.Config
  opts = {
    -- 全局按键：j/k 上下移动，l 展开/跳转（有折叠节点且未展开→展开，否则跳转文件），h 折叠收起
    keys = {
      h = 'fold_close',
      l = {
        action = function(self, ctx)
          if ctx.node and not ctx.node:is_leaf() and ctx.node.folded then
            self:fold(ctx.node, { action = 'open' })
          elseif ctx.item then
            self:jump(ctx.item)
          end
        end,
        desc = 'Expand or jump',
      },
      gf = {
        action = function(self, ctx)
          if ctx.item then
            self:jump(ctx.item)
            self:close()
          end
        end,
        desc = 'Jump and close',
      },
    },

    modes = {
      diagnostics = {
        win = { position = 'bottom', size = 10, wo = { foldlevel = 0 } },
      },
      qflist = {
        focus = true,
        win = { position = 'left', size = 38, wo = { foldlevel = 0 } },
      },
      -- LSP 引用视图：类似 VSCode「按文件分组的引用列表」
      lsp_references = {
        win = { position = 'left', size = 38 },
      },

      -- 文档符号树（go 打开）：左侧、默认展开整棵「干净大纲」（见 lsp.lua 的 go opener 设 foldlevel）
      -- 自定义名 doc_symbols（不复用内置 symbols，避免继承其 kind 白名单——那会硬删 Variable/Constant）
      doc_symbols = {
        desc = 'Document symbols',
        mode = 'lsp_document_symbols',
        focus = true,
        win = { position = 'left', size = 40 },
        -- 符号过滤（函数式，一次遍历）。默认只留「结构」，按 H 切 symbols_state.show_locals 全部还原：
        --   1. luals 把 if/for 等控制流当成 Package 伪符号 → 仅 lua 文件剔除（始终隐藏，非真符号）
        --   以下受 symbols_state.show_locals 控制（按 H 切换显示，见 keys.H）：
        --   2. import 导入语句（顶层叶子符号，无父节点可折叠，只能直接过滤）
        --   3. 「细节符号」噪音：
        --      a) 函数体内的局部变量（解构 props、useState/useRef 结果等）
        --      b) 对象字面量的成员值（如 { opacity: 0, y: 20 } 里的 opacity/y）
        --      → 只隐藏「非函数」的；函数本身、箭头函数 const、含函数的对象一律保留
        --      → class/interface/enum 成员的 parent 不是 Variable，不受影响，照常显示
        --   顶层符号（含顶层 Variable/Constant）一律保留
        --
        -- 关键坑（已用 tsgo 实测验证）：
        --   - import / 局部变量的 kind 都是 Variable，detail/tags 也为空，无法靠 kind 区分
        --   - trouble 给的 item.item.text 是「从符号列起切片」的（如 "foo, bar } from ..."），不是整行，不可靠
        --   - 多行 import 的成员各自落在续行（如 "  Component,"），行首也不是 import 关键字
        --   → import：扫 buffer 算出「import 语句覆盖的行号集合」（多行感知），按 item.pos 判断
        --   → 局部变量：沿 item.parent 上溯判断是否在函数体内；trouble 的 item 无 children 列表，
        --     故先正扫一遍把「含函数后代」的符号标出来，避免隐藏它们导致内部函数被孤立
        filter = function(items)
          -- 各语言 import 语句的「行首关键字」，覆盖主流语言
          local IMPORT_KW = {
            import = true,           -- JS/TS、Python、Java、Kotlin、Dart、Swift、Scala
            from = true,             -- Python: from x import y
            use = true,              -- Rust、PHP
            using = true,            -- C#、C++
            require = true,          -- CommonJS、Ruby、PHP、Lua 裸调用
            require_relative = true, -- Ruby
            include = true,          -- PHP、Ruby
            alias = true,            -- Elixir
            extern = true,           -- Rust: extern crate
          }
          -- CSS/SCSS at-rule 导入：@import / @use / @forward
          local CSS_AT = { import = true, use = true, forward = true }

          -- 视为「函数」的 kind（这些及其后代结构永远保留）
          local FN_KIND = { Function = true, Method = true, Constructor = true }
          -- 可能是「局部变量噪音」的 kind
          local VAR_KIND = { Variable = true, Constant = true, Field = true, Property = true, EnumMember = true }

          local function is_import_line(line)
            line = vim.trim(line)

            local at = line:match('^@([%a_]+)')
            if at then return CSS_AT[at] == true end

            -- 贪婪取行首第一个词，天然带边界，不会误伤 imports / useState 等
            local first = line:match('^([%w_]+)')
            return first ~= nil and IMPORT_KW[first] == true
          end

          -- buffer 整行缓存（import 段扫描 + 函数值判断都要用整行，item.item.text 不可靠）
          local lines_cache = {}
          local function buf_lines(buf)
            if not lines_cache[buf] then lines_cache[buf] = vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
            return lines_cache[buf]
          end

          -- 计算 buffer 内所有 import 语句覆盖的 0-based 行号集合（对齐 LSP range.start.line）
          local imp_cache = {}
          local function import_lines(buf)
            if imp_cache[buf] then return imp_cache[buf] end

            local set, in_block = {}, false
            for i, raw in ipairs(buf_lines(buf)) do
              local line, lnum = vim.trim(raw), i - 1

              if in_block then
                set[lnum] = true
                -- 多行 import 段收尾：闭合括号或 from 子句
                if line:find('[}%)]') or line:match('^from%f[%W]') then in_block = false end
              elseif is_import_line(line) then
                set[lnum] = true
                -- 起始行打开括号且本行未闭合 → 进入多行 import 段
                if line:find('[{%(]') and not line:find('[}%)]') then in_block = true end
              end
            end

            imp_cache[buf] = set
            return set
          end

          -- 符号声明是否「函数值」（箭头函数 / function 表达式）：看声明起始几行有无 => 或 function
          local function is_function_valued(item, buf)
            local lines = buf_lines(buf)
            local from = item.pos and item.pos[1] or 0
            local to = math.min(item.end_pos and item.end_pos[1] or from, from + 2)
            for r = from, to do
              local l = lines[r]
              if l and (l:find('=>') or l:find('%f[%w]function%f[%W]')) then return true end
            end
            return false
          end

          -- 沿 parent 上溯：是否处在某个函数体内
          local function inside_function(item)
            local p = item.parent
            while p do
              if FN_KIND[p.kind] then return true end
              p = p.parent
            end
            return false
          end

          -- 正扫：标出所有「含函数后代」的符号（隐藏它们会让内部函数变孤儿，故保留）
          local has_fn_descendant = {}
          for _, it in ipairs(items) do
            if FN_KIND[it.kind] then
              local p = it.parent
              while p do has_fn_descendant[p] = true; p = p.parent end
            end
          end

          return vim.tbl_filter(function(item)
            local buf = item.buf
            local ft = buf and vim.bo[buf].filetype

            if ft == 'lua' and item.kind == 'Package' then return false end
            -- import 也归入 show_locals 开关：按 H 切到「显示」时一并还原
            if not symbols_state.show_locals and buf and item.pos and import_lines(buf)[item.pos[1] - 1] then
              return false
            end

            -- 「细节符号」噪音：非函数值、且自身不含函数后代的 VAR_KIND，处于
            --   ① 函数体内（局部变量）或 ② 对象字面量内（直接 parent 是 Variable/Constant）时隐藏
            -- （H 可切换；class/interface/enum 成员的 parent 不是 VAR_KIND，不受影响）
            local in_object = item.parent and VAR_KIND[item.parent.kind]
            if not symbols_state.show_locals
              and buf
              and VAR_KIND[item.kind]
              and not has_fn_descendant[item]
              and not is_function_valued(item, buf)
              and (inside_function(item) or in_object)
            then
              return false
            end

            return true
          end, items)
        end,
        keys = {
          -- 面板内直接 vertical resize：绕开 smart-splits 对 nofile 面板的方向/焦点 bug
          -- （buffer-local 映射，仅在符号面板内覆盖全局 <C-A-Arrow>）
          ['<C-A-Right>'] = { action = function() vim.cmd('vertical resize +3') end, desc = 'Widen panel' },
          ['<C-A-Left>']  = { action = function() vim.cmd('vertical resize -3') end, desc = 'Narrow panel' },
          -- 符号树没有诊断 severity，禁用 trouble 默认的 s(severity 过滤，会显示 Filter: ERROR)
          -- 设 false 即不注册 buffer-local s，让全局 flash 的 s 在面板内生效
          s = false,
          -- H：切换「显示/隐藏细节符号」（import + 函数内局部变量 + 对象字面量成员值）
          -- 翻转开关后 refresh 触发 filter 重跑（h 仍是 fold_close 收起节点，不冲突）
          H = {
            action = function(self)
              symbols_state.show_locals = not symbols_state.show_locals
              local on = symbols_state.show_locals
              vim.notify((on and ' 显示' or ' 隐藏') .. '细节符号（import / 局部变量 / 对象属性）', vim.log.levels.INFO)
              self:refresh()
            end,
            desc = 'Toggle detail symbols',
          },
          -- l：有子节点且折叠 → 展开；有子节点且已展开 / 叶子节点 → 跳转到文件位置（同 CR）
          -- node.folded 在每次渲染时由 renderer:is_folded() 写入，反映当前折叠状态
          l = {
            action = function(self, ctx)
              if ctx.node and not ctx.node:is_leaf() and ctx.node.folded then
                self:fold(ctx.node, { action = 'open' })
              elseif ctx.item then
                self:jump(ctx.item)
              end
            end,
            desc = 'Expand or jump',
          },
        },
      },
    },
  },
}
