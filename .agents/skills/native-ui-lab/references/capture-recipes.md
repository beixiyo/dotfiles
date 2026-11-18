# 截图、取样与对比命令（按平台）

历史命令示例，未记录完整系统和工具版本。按目标桌面、会话权限和已安装工具选择，不因某条命令失败就推断平台不支持。退出应用、改变前台焦点等操作可能破坏现场，只有实验确需且在授权范围内才执行

## 区域截图

```bash
# macOS：-x 不出声；先以实际截图尺寸核对 -R 坐标与像素的缩放关系，副显示器 x 可为负
screencapture -x -R 1145,700,599,207 out.png

# Linux X11
import -window root -crop 599x207+1145+700 out.png
scrot -a 1145,700,599,207 out.png
# Linux Wayland：grim 依赖合成器支持，也可核实桌面提供的 portal 或截图接口
grim -g "1145,700 599x207" out.png
```

```powershell
# Windows：当前交互桌面的截图示例，受会话、桌面与权限边界影响
Add-Type -AssemblyName System.Drawing
$b = New-Object Drawing.Bitmap 599,207
[Drawing.Graphics]::FromImage($b).CopyFromScreen(1145,700,0,0,$b.Size)
$b.Save('out.png')
```

macOS 截图黑屏、空白或缺少内容时，检查屏幕录制权限、捕获目标和保护内容等因素；不要仅凭黑图确定原因

## 读别的进程的窗口矩形

```bash
# macOS：Swift CLI 读 CGWindowListCopyWindowInfo，按实际权限检查可见字段，见 electron-lab.md
./settings-window            # 主窗口 JSON
./settings-window --dump     # 该进程全部在屏窗口的 layer / bounds

# Linux X11 示例；Wayland 需核实合成器或桌面提供的窗口信息接口
xdotool search --name "Settings" | head -1 | xargs xdotool getwindowgeometry --shell
xwininfo -name "Settings" | grep -E "Absolute|Width|Height"
```

```powershell
# Windows：GetWindowRect 示例，检查句柄及返回值
Add-Type @"
using System; using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public class W { [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); }
"@
$p = Get-Process -Name "SystemSettings" | Select-Object -First 1
$r = New-Object RECT; [W]::GetWindowRect($p.MainWindowHandle, [ref]$r); $r
```

## 像素取样

```bash
# 一次取多点，避免 shell 循环的引号问题；三平台同样命令（ImageMagick）
magick user.png -format 'card=%[pixel:p{300,290}] pill=%[pixel:p{300,362}]\n' info:
```

相同条件下的取样可证明颜色差异；单点 RGB 不能确定材质身份，背景、着色、模糊和色彩管理都可能影响结果

## 区域对比度量化

```bash
# 固定背景、取景和内容后，区域标准差可辅助比较可见结构；它不是透明度测量值
for f in *.png; do
  printf '%-16s mean=%s sd=%s\n' "$f" \
    "$(magick "$f" -crop 500x60+50+35 -colorspace Gray -format '%[fx:int(mean*255)]' info:)" \
    "$(magick "$f" -crop 500x60+50+35 -colorspace Gray -format '%[fx:standard_deviation*255]' info:)"
done | sort -t= -k3 -n -r
```

裁剪区域里不能有自己画的文字或按钮，否则标准差被它们主导

## 拼图对比

```bash
# macOS 字体路径示例；Linux 换 /usr/share/fonts 下任一 ttf，Windows 换 C:/Windows/Fonts/arial.ttf
magick montage -font /System/Library/Fonts/Supplemental/Arial.ttf -pointsize 18 -label '%t' \
  a.png b.png c.png d.png -tile 2x2 -geometry +12+12 -background '#ddd' compare.png
open compare.png        # Linux: xdg-open；Windows: Start-Process
```

默认字体不可用而报 `unable to read font` 时，显式指定本机存在的字体

## 控制别的 App

```bash
# macOS
open -a "System Settings"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
osascript -e 'quit app "System Settings"'                   # 完全退出，清掉它进程内的授权凭证缓存
defaults read -g AppleInterfaceStyle                        # Dark，或报错表示浅色
security authorizationdb read system.preferences.security   # 某操作要不要弹密码、凭证缓存多久

# Linux
xdg-open "settings://"   # 视桌面环境；GNOME 用 gnome-control-center privacy
pkill -x gnome-control-center
gsettings get org.gnome.desktop.interface color-scheme      # 'prefer-dark' 或 'default'
```

```powershell
# Windows
Start-Process "ms-settings:privacy"
Stop-Process -Name "SystemSettings"
Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' AppsUseLightTheme   # 0 = 深色
```

## 自动操作别的 App 的 UI

| 平台 | 工具 | 前置条件 |
| --- | --- | --- |
| macOS | `osascript` + `System Events`（点按钮、敲键） | 检查辅助功能和自动化权限；对象解析错误也可能源于名称或对象不存在 |
| Linux X11 | `xdotool click / key / type` | 需可访问目标 X 会话 |
| Linux Wayland | 合成器接口、portal 或输入模拟工具 | 核实当前桌面支持及权限，必要时由用户操作 |
| Windows | PowerShell UIAutomation、`[System.Windows.Forms.SendKeys]` | 核实会话、焦点与进程权限边界 |

## 观测偶现的系统弹层

自己触发不了时脚本只负责观测，让用户去操作：

```bash
for i in $(seq 1 120); do
  printf '%s %s\n' "$(date +%H:%M:%S)" "$(./settings-window --dump)" >> dump.log
  sleep 1
done
```

后台跑起来后告诉用户「现在去触发，弹出后停 3 到 5 秒」，事后 `grep` 日志找多出来的窗口
