-- 让 y/d/p 默认走系统剪贴板（+ 寄存器）
vim.opt.clipboard = "unnamedplus"

-- 完全不用外部剪贴板（y/p 只影响 Vim 内部）
-- vim.opt.clipboard = ""

-- 选择剪贴板 + 系统剪贴板都同步
-- vim.opt.clipboard = "unnamed,unnamedplus"

-- =======================
-- provider 选择策略
--
-- 历史缺陷（本次修复的目标）：
--   provider 只在 nvim 启动那一刻判定一次就被「冻结」。持久化 tmux 里，nvim 在宿主机
--   本地启动 → 冻结成 wl-clipboard；之后从外网 SSH attach 上来，nvim 还是那套
--   wl-clipboard，yy 永远写宿主机剪贴板，到不了你面前的终端。只能杀掉 tmux 逼 nvim
--   重启重算 → 丢失全部工作进度
--
-- 两类 provider 的本质：
--   * wl-clipboard / xclip 是「机器相对」—— 永远同步 nvim 所在机器的剪贴板。本地完美、
--     全双向；但 SSH 进来时落在服务器，到不了你面前
--   * OSC52 是「终端相对」—— 复制总能到达你此刻所在的终端（本地 kitty / 远程 attach 的
--     SSH 客户端皆可，经 tmux 转发亦稳定）。但 paste(read) 多数终端默认拒读（kitty 拒读、
--     wezterm 无此选项），经 tmux 转发 read 极不稳定（neovim#29788），实测会卡 10s
--
-- 修复思路：把「写」与「读」拆开，让写方向不依赖启动时判定
--   * copy：终端 UI 发 OSC52；同时尽量写本机系统剪贴板（pbcopy / wl-copy / xclip）
--       - 本地终端：系统剪贴板照旧可用，OSC52 冗余无害
--       - 远程 attach：OSC52 到达你家终端；本机剪贴板命令即使落在宿主机也无害
--       - GUI / headless：没有终端 OSC52 通道，只写本机系统剪贴板，避免 Neovide 卡死
--   * paste：OSC52 读不可靠，故仍按「此刻是否本地」运行时判定（不冻结；判定结果最多复用 1 秒，
--       NVIM_FORCE_* 逃生舱优先、不经缓存）：
--       本地 → pbpaste / wl-paste / xclip（保留「外部应用 Ctrl-c → nvim p」入站粘贴）；
--       远程 → 内部寄存器兜底
--
-- 逃生舱：NVIM_FORCE_OSC52=1 只走 OSC52（copy 不再 wl-copy）；NVIM_FORCE_WL=1 只走本地
-- =======================

-- 本会话是否存在「本地（非 SSH）客户端」
-- 背景：持久化共享 tmux server 里，session 级 SSH_TTY/SSH_CONNECTION 是 server 启动时的陈旧快照，
-- 只能看客户端进程本身：逐 client 的远程判定由 vv-utils.sys.tmux_clients 提供（祖先链含 sshd / mosh-server，跨平台）
-- 为何不挑「当前客户端」：本地 kitty 与 Claude 的 SSH 常并存于同一会话，挑当前客户端会被
-- 谁最近活跃左右、不稳定。改判「只要有一个本地客户端在线就认为人在本地」，正好覆盖
-- 「kitty + SSH 并存」=本地；只有「全是 SSH 客户端」才算远程
-- 粘贴时才调用（vv-utils 由插件系统加载，晚于本文件），不可用时按「非本地」回退内部寄存器
local function has_local_tmux_client()
  if not vim.env.TMUX then return false end
  local ok, sys = pcall(require, "vv-utils.sys")
  if not ok then return false end
  local clients = sys.tmux_clients({ target = vim.env.TMUX_PANE })
  if not clients then return false end
  for _, c in ipairs(clients) do
    if not c.remote then return true end
  end
  return false
end

-- 实际判定「本地 / 远程」：会同步执行外部命令（tmux list-clients / ps -A，约数十 ms）
local function detect_local()
  -- 持久 tmux 里 env 陈旧 → 看本会话客户端：有本地客户端才算本地
  if vim.env.TMUX then return has_local_tmux_client() end
  -- 非 tmux：交给 vv-utils.sys.is_remote（先看 nvim 自身进程祖先链是否经 sshd / mosh-server，
  -- 再按 SSH 环境变量兜底：两端皆回环不算远程）；vv-utils 不可用时只看环境变量
  local ok, sys = pcall(require, "vv-utils.sys")
  if ok then return not sys.is_remote() end
  return not (vim.env.SSH_CONNECTION or vim.env.SSH_TTY or vim.env.SSH_CLIENT)
end

-- 判定结果缓存 1 秒：每次粘贴都同步跑外部命令（非 tmux 时 ps -A 约 25ms），
-- 宏 / 连续 p 会被逐次拖慢；attach / detach 是人为操作，1 秒内的滞后可以接受，仍不会被启动时判定冻结
local LOCAL_CACHE_TTL_NS = 1e9
local local_cache = { value = false, at = nil }

-- 此刻是否「本地」（仅 paste 方向需要：决定读宿主机系统剪贴板还是回退内部寄存器）
-- 每次粘贴调用，判定结果最多复用 1 秒；逃生舱环境变量不经缓存，始终优先生效
local function is_local_now()
  if vim.env.NVIM_FORCE_OSC52 then return false end
  if vim.env.NVIM_FORCE_WL then return true end
  if local_cache.at and vim.uv.hrtime() - local_cache.at < LOCAL_CACHE_TTL_NS then return local_cache.value end
  local_cache.value = detect_local()
  -- 时间戳取判定结束时刻：退化时判定本身可能 ≥1s（命令超时），取开始时刻会写入即过期
  local_cache.at = vim.uv.hrtime()
  return local_cache.value
end

local function has_attached_ui()
  return #vim.api.nvim_list_uis() > 0
end

local function should_copy_osc52()
  if vim.env.NVIM_FORCE_WL then return false end
  if vim.g.neovide or vim.fn.has('gui_running') == 1 then return false end
  return has_attached_ui()
end

-- 本地系统剪贴板命令（macOS / Wayland / X11）
local function local_copy_cmd()
  if vim.fn.executable("pbcopy") == 1 then return { "pbcopy" } end
  if vim.fn.executable("wl-copy") == 1 then return { "wl-copy" } end
  if vim.fn.executable("xclip") == 1 then return { "xclip", "-selection", "clipboard" } end
  return nil
end

local function local_paste_cmd()
  if vim.fn.executable("pbpaste") == 1 then return { "pbpaste" } end
  if vim.fn.executable("wl-paste") == 1 then return { "wl-paste", "--no-newline" } end
  if vim.fn.executable("xclip") == 1 then return { "xclip", "-selection", "clipboard", "-o" } end
  return nil
end

-- WSL 特殊处理换行
if vim.fn.has('wsl') == 1 then
  vim.g.clipboard = {
    name = 'win32yank-wsl',
    copy = {
      ['+'] = 'win32yank.exe -i --crlf',
      ['*'] = 'win32yank.exe -i --crlf',
    },
    paste = {
      ['+'] = 'win32yank.exe -o --lf',
      ['*'] = 'win32yank.exe -o --lf',
    },
    cache_enabled = 0,
  }
elseif vim.fn.has("nvim-0.10") == 1 then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok then
    local osc52_copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    }

    -- 写方向：无条件 OSC52 + 本地 wl-copy，不看「本地/远程」，因而永不被启动时判定冻结
    local function make_copy(reg)
      return function(lines, regtype)
        -- 1) OSC52 → 到达你此刻所在的终端（本地 kitty / 远程 attach 的 SSH 客户端皆可），
        --    经 tmux 转发亦稳定。这是修复点：不依赖 nvim 启动时机
        --    GUI / headless 没有终端 OSC52 通道，不能写 OSC52，否则 Neovide 会卡在复制路径上
        if should_copy_osc52() then
          osc52_copy[reg](lines, regtype)
        end
        -- 2) 额外写本地系统剪贴板：本地保留「nvim y → 外部应用粘贴」直通；
        --    远程时落宿主机剪贴板、无人读、无害
        if not vim.env.NVIM_FORCE_OSC52 then
          local cmd = local_copy_cmd()
          if cmd then
            vim.fn.system(cmd, table.concat(lines, "\n"))
          end
        end
      end
    end

    -- 读方向：内部寄存器兜底（远程；避免 OSC52 read 卡 10s）
    local function reg_paste()
      return {
        vim.fn.split(vim.fn.getreg(""), "\n"),
        vim.fn.getregtype(""),
      }
    end

    -- 本地：实时读宿主机系统剪贴板（保留外部应用入站粘贴）；远程：回退内部寄存器
    local function make_paste()
      return function()
        if is_local_now() then
          local cmd = local_paste_cmd()
          if cmd then
            local out = vim.fn.system(cmd)
            if vim.v.shell_error == 0 then
              -- 末尾换行：源自「整行复制」→ 按行型(V)粘贴，更符合直觉
              local has_final_nl = out:sub(-1) == "\n"
              local body = out:gsub("\n$", "")
              return { vim.split(body, "\n"), has_final_nl and "V" or "v" }
            end
          end
        end
        return reg_paste()
      end
    end

    vim.g.clipboard = {
      name = "OSC52 + local",
      copy = {
        ["+"] = make_copy("+"),
        ["*"] = make_copy("*"),
      },
      paste = {
        ["+"] = make_paste(),
        ["*"] = make_paste(),
      },
    }
  end
end
