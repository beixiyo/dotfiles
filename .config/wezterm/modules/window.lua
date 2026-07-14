-- ╭─────────────────────────────────────────────────────╮
-- │       窗口尺寸 / 屏幕居中 / 背景图（可选）           │
-- ╰─────────────────────────────────────────────────────╯

local wezterm = require('wezterm')

local M = {}

-- 平台检测（target_triple 官方文档确认可用；WSL 宿主的 triple 含 "windows"）
-- 注：在 WSL 内运行 WezTerm 时 target_triple 为 linux，可用 wezterm.running_under_wsl() 区分，此处无需区分
local target      = wezterm.target_triple
local is_windows  = target:find('windows') ~= nil
local is_mac      = target:find('darwin')  ~= nil
local is_linux    = not is_windows and not is_mac

-- true = 百分比尺寸模式；false = 根据背景图宽高比计算
local USE_PERCENT_SIZE = true
local background_image_path = 'C:/pic/Camera/girl.jpg'

local function get_image_dimensions(image_path)
  local success, image = pcall(function()
    return wezterm.image_from_file(image_path)
  end)
  if success and image then
    return image:get_width(), image:get_height()
  end
  return 1440, 1798
end

local function calculate_window_size(image_path, screen_width, screen_height)
  local img_width, img_height = get_image_dimensions(image_path)
  local aspect_ratio = img_width / img_height

  local max_width, max_height = screen_width * 0.8, screen_height * 0.8
  local width, height
  if max_width / max_height > aspect_ratio then
    height, width = max_height, max_height * aspect_ratio
  else
    width, height = max_width, max_width / aspect_ratio
  end
  return width, height
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
      width  = screen.width * 0.8
      height = screen.height * 0.8
    else
      width, height = calculate_window_size(background_image_path, screen.width, screen.height)
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
