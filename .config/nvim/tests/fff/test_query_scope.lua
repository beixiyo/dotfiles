-- fff query 辅助模块 × 真实 fff 引擎集成测试（fixture 目录 + 独立 db，不碰用户 frecency/历史）
-- 验证的契约：
--   1. scope_glob 生成的 token 交给 fff 后恰好命中目标路径：以索引根锚定（lib/src 不能混进 src 的结果）、
--      顶层文件、多选合并、中文文件名均可用；无法安全表达的路径返回 nil 交给调用方回退
--   2. split 的 grep/files 分类与 fff 解析器一致：grep 模式下 `arr[0]` 仍是搜索文本
--   3. replace_filters（<M-p> 确认）整体替换筛选 token，输入按 telescope 时代的 glob 语义编译：
--      相对路径任意深度匹配（修复前原样写入，fff glob 以索引根锚定，`pack/**` 命中 0）、`./` 锚定根、
--      多条正向规则之间 OR（fff 多个 glob token 是 AND）、顶层逗号不拆 brace
local H = dofile('tests/helpers.lua')
local T, child = H.new_set({ 'VV_TEST_FFF' })

T['scope 锚定、token 分类与筛选替换'] = function()
  child.lua_func(function()
    local base = vim.fn.tempname()
    local root = base .. '/repo'
    local files = {
      ['src/a.lua'] = 'needle arr[0]',
      ['src/sub/b.lua'] = 'needle',
      ['lib/src/a.lua'] = 'needle',
      ['init.lua'] = 'needle',
      ['docs/说明.md'] = 'needle',
      ['other.md'] = 'needle',
      ['lua/pack/x.lua'] = 'needle',
      ['.hidden/h.lua'] = 'needle',
    }
    for rel, content in pairs(files) do
      vim.fn.mkdir(vim.fs.dirname(root .. '/' .. rel), 'p')
      vim.fn.writefile({ content }, root .. '/' .. rel)
    end

    -- git 仓库内 fff 才索引隐藏文件（walk/ripgrep.rs `.hidden(!is_git_repo)`），与日常使用场景一致
    vim.fn.system({ 'git', '-C', root, 'init', '-q' })

    vim.cmd.cd(root)
    require('fff').setup({
      base_path = root,
      lazy_sync = true,
      frecency = { db_path = base .. '/frecency' },
      history = { db_path = base .. '/history' },
      logging = { enabled = false },
    })
    require('fff.core').ensure_initialized()
    require('fff.file_picker').setup()
    check(require('fff.file_picker').wait_for_initial_scan(15000), 'fff 初始索引超时')

    ---@return string[] 命中文件的相对路径（去重、排序）
    local function grep_files(query)
      local result = require('fff').content_search(query, { page_size = 500 })
      local seen = {}
      for _, item in ipairs(result.items) do seen[item.relative_path] = true end
      local list = vim.tbl_keys(seen)
      table.sort(list)
      return list
    end

    local Query = require('plugins.specs.tools.fff.query')

    local function scope(...)
      local paths = vim.tbl_map(function(rel) return root .. '/' .. rel end, { ... })
      return Query.scope_glob(paths, root)
    end

    -- 1. scope_glob 锚定
    eq(grep_files(scope('src') .. ' needle'), { 'src/a.lua', 'src/sub/b.lua' },
      '目录范围必须锚定到索引根：lib/src/a.lua 不得命中')
    eq(grep_files(scope('init.lua') .. ' needle'), { 'init.lua' }, '顶层文件范围只命中该文件')
    eq(grep_files(scope('docs/说明.md') .. ' needle'), { 'docs/说明.md' }, '中文文件名范围只命中该文件')
    eq(grep_files(scope('src/a.lua', 'docs') .. ' needle'), { 'docs/说明.md', 'src/a.lua' },
      '多选路径合并后命中各自范围的并集')
    eq(scope(''), '', '范围等于索引根时返回空 token（不限定）')
    eq(Query.scope_glob({ base }, root), nil, '索引根之外的路径必须返回 nil 由调用方回退')
    eq(Query.scope_glob({ root .. '/has space.lua' }, root), nil, '含空白的路径无法作为单个 token，必须返回 nil')

    -- 2. 分类与 fff 解析器一致
    eq(Query.split('arr[0] foo? *.lua src/ !test', 'grep'),
      { text = { 'arr[0]', 'foo?' }, filters = { '*.lua', 'src/', '!test' } },
      'grep 模式下 [ 与 ? 属于搜索文本，只有扩展名 / 路径段 / 取反是筛选')
    eq(grep_files('arr[0]'), { 'src/a.lua' }, 'fff 引擎在 grep 模式同样把 arr[0] 当作搜索文本')
    eq(Query.split('arr[0] git:modified', 'files').filters, { 'arr[0]', 'git:modified' },
      'files 模式下任何通配符 token 与 git: 都是筛选')

    -- 3. <M-p> 确认后整体替换筛选
    local function filtered(input, query)
      local q = assert(Query.replace_filters(query or 'needle', input, 'grep'))
      return grep_files(q)
    end
    eq(filtered('pack/**'), { 'lua/pack/x.lua' }, '相对 glob 必须任意深度匹配，不能只锚定索引根')
    eq(filtered('src'), { 'lib/src/a.lua', 'src/a.lua', 'src/sub/b.lua' }, '裸路径匹配任意深度的本体与后代')
    eq(filtered('./src'), { 'src/a.lua', 'src/sub/b.lua' }, '`./` 前缀锚定索引根')
    eq(filtered('src/sub, lua/pack'), { 'lua/pack/x.lua', 'src/sub/b.lua' }, '多条正向规则之间是 OR')
    eq(filtered('*.{md,json}'), { 'docs/说明.md', 'other.md' }, '顶层逗号拆分不能拆开 brace')
    eq(filtered('.md'), { 'docs/说明.md', 'other.md' }, '`.md` 是 `*.md` 的简写')
    eq(filtered('src, !lib'), { 'src/a.lua', 'src/sub/b.lua' }, '排除规则与正向规则同时生效')
    eq(filtered('.hidden'), { '.hidden/h.lua' }, '隐藏目录名也能作为路径筛选')
    eq(filtered('*.md', 'needle *.lua'), { 'docs/说明.md', 'other.md' }, '替换后旧的 *.lua 不再生效')

    local replaced = assert(Query.replace_filters('needle *.lua', '*.md', 'grep'))
    eq(Query.split(replaced, 'grep').text, { 'needle' }, '替换筛选时保留搜索词')
    check(replaced:sub(-1) == ' ', '替换结果带尾随空格供继续输入')
    eq(Query.replace_filters('needle *.lua', '', 'grep'), 'needle ', '清空弹窗输入即移除全部筛选')
    eq(Query.replace_filters('x', 'git:modified', 'files'), 'x git:modified ', 'fff 原生 key:value 约束原样保留')
    local bad, err = Query.replace_filters('needle', '../up', 'grep')
    check(bad == nil and err ~= nil, '无法编译的输入（../）必须返回错误而不是写坏 query')

    pcall(require('fff.fuzzy').cleanup_file_picker)
    vim.fn.delete(base, 'rf')
  end)
end

return T
