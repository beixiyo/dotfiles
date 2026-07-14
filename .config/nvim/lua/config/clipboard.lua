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
--   * paste：OSC52 读不可靠，故仍按「此刻是否本地」实时判定（每次粘贴现算，不冻结）：
--       本地 → pbpaste / wl-paste / xclip（保留「外部应用 Ctrl-c → nvim p」入站粘贴）；
--       远程 → 内部寄存器兜底
--
-- 逃生舱：NVIM_FORCE_OSC52=1 只走 OSC52（copy 不再 wl-copy）；NVIM_FORCE_WL=1 只走本地
-- =======================

-- 某进程的 environ 是否含 SSH 连接标记（判断该 tmux 客户端是否经 SSH 连入）
-- 背景：持久化共享 tmux server 里，session 级 SSH_TTY/SSH_CONNECTION 是 server 启动时的陈旧
-- 快照；但「客户端进程」（tmux attach 进程）的 environ 永远是本次连接的真实环境，查它最可靠
-- （已实测可靠区分本地 kitty 与 SSH 客户端）
local function pid_is_ssh(pid)
  local f = io.open("/proc/" .. pid .. "/environ", "rb")
  if not f then return false end
  local data = f:read("*a") or ""
  f:close()
  -- environ 以 \0 分隔，子串匹配即可命中 `SSH_CONNECTION=...`
  return data:find("SSH_CONNECTION=", 1, true) ~= nil or data:find("SSH_TTY=", 1, true) ~= nil
end

-- 本会话是否存在「本地（非 SSH）客户端」
-- 为何不挑「当前客户端」：本地 kitty 与 Claude 的 SSH 常并存于同一会话，挑当前客户端会被
-- 谁最近活跃左右、不稳定。改判「只要有一个本地客户端在线就认为人在本地」，正好覆盖
-- 「kitty + SSH 并存」=本地；只有「全是 SSH 客户端」才算远程
local function has_local_tmux_client()
  if not vim.env.TMUX then return false end
  local pane = vim.env.TMUX_PANE or ""
  local sid = ""
  if pane ~= "" then
    sid = vim.fn.system("tmux display-message -p -t '" .. pane .. "' '#{session_id}' 2>/dev/null"):gsub("%s+", "")
  end
  local cmd = sid ~= ""
    and ("tmux list-clients -t '" .. sid .. "' -F '#{client_pid}' 2>/dev/null")
    or "tmux list-clients -F '#{client_pid}' 2>/dev/null"
  local out = vim.fn.system(cmd)
  if out == "" then return false end
  for pid in out:gmatch("%d+") do
    if not pid_is_ssh(pid) then return true end
  end
  return false
end

-- 此刻是否「本地」（仅 paste 方向需要：决定读宿主机系统剪贴板还是回退内部寄存器）
-- 每次粘贴实时调用，不缓存、不冻结
local function is_local_now()
  if vim.env.NVIM_FORCE_OSC52 then return false end
  if vim.env.NVIM_FORCE_WL then return true end
  -- 持久 tmux 里 env 陈旧 → 看本会话客户端：有本地客户端才算本地
  if vim.env.TMUX then return has_local_tmux_client() end
  -- 非 tmux：直接看本进程 SSH 迹象
  return not (vim.env.SSH_CONNECTION or vim.env.SSH_TTY or vim.env.SSH_CLIENT)
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
        --    GUI / headless 没有终端 OSC52 通道，不能写 OSC52，否则 Neovide 会卡在复制路径上。
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
