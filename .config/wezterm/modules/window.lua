-- ╭─────────────────────────────────────────────────────╮
-- │       窗口尺寸 / 屏幕居中 / 背景比例（可选）         │
-- ╰─────────────────────────────────────────────────────╯

local wezterm = require('wezterm')

local M = {}

-- 平台检测（target_triple 官方文档确认可用；WSL 宿主的 triple 含 "windows"）
-- 注：在 WSL 内运行 WezTerm 时 target_triple 为 linux，可用 wezterm.running_under_wsl() 区分，此处无需区分
local target      = wezterm.target_triple
local is_windows  = target:find('windows') ~= nil
local is_mac      = target:find('darwin')  ~= nil
local is_linux    = not is_windows and not is_mac

-- true = 屏幕宽高各取 80%；false = 按配置的背景图片尺寸保持宽高比
local USE_PERCENT_SIZE = true
local BACKGROUND_IMAGE_SIZE = {
  width = 1440,
  height = 1798,
}

---按背景图片宽高比计算不超过屏幕 80% 的窗口尺寸
---@param screen_width number
---@param screen_height number
---@return number width
---@return number height
local function calculate_window_size(screen_width, screen_height)
  local aspect_ratio = BACKGROUND_IMAGE_SIZE.width / BACKGROUND_IMAGE_SIZE.height
  local max_width = screen_width * 0.8
  local max_height = screen_height * 0.8

  if max_width / max_height > aspect_ratio then
    return max_height * aspect_ratio, max_height
  end

  return max_width, max_width / aspect_ratio
end

function M.apply(_config)
  -- WSL（Windows 宿主）：默认启动 WSL 到指定目录
  if is_windows then
    _config.default_prog = { 'wsl.exe', '--cd', '~/code/frontend' }
  end

  wezterm.on('gui-startup', function(cmd)
    local screen = wezterm.gui.screens().active
    local width, height
    if USE_PERCENT_SIZE then
      width = screen.width * 0.8
      height = screen.height * 0.8
    else
      width, height = calculate_window_size(screen.width, screen.height)
    end

    local default_args = {
      position = {
        x = (screen.width - width) / 2,
        y = (screen.height - height) / 2,
        origin = { Named = screen.name },
      },
    }

    -- Linux 原生：启动目录设为 ~/code/frontend
    if is_linux then
      default_args.cwd = wezterm.home_dir .. '/code/frontend'
    end

    local _tab, _pane, window = wezterm.mux.spawn_window(cmd or default_args)
    window:gui_window():set_inner_size(width, height)
  end)
end

return M
