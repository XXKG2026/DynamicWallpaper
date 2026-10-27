# 动态壁纸 · DynamicWallpaper

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2010.13%2B-lightgrey.svg)]()

把任意 MP4 视频铺满 macOS 桌面，作为动态壁纸播放。原生 Swift + AppKit 实现，无第三方依赖，体积不到 1 MB。

> A lightweight macOS live-wallpaper app that plays any MP4 as your desktop background. Pure Swift + AppKit, no dependencies.

<p align="center">
  <img src="docs/icon.png" width="180" alt="icon">
</p>

---

## 为什么需要它

macOS 系统设置里只支持静态图片，没有视频壁纸选项。这个工具通过创建一个特殊层级的窗口来实现：

| 层级 | 数值 | 内容 |
|---|---|---|
| 桌面壁纸图片 | -2147483623 | 系统静态壁纸 |
| **视频窗口** | **-2147483613** | ← 本项目 |
| 桌面图标 | -2147483603 | 桌面上的文件 |
| 普通窗口 | 0 | 其他应用 |

视频窗口夹在壁纸和图标之间，所以：

- 视觉上就是桌面背景，**桌面图标和所有应用窗口都正常盖在上面**
- `ignoresMouseEvents = true` → 鼠标点击直接穿透，不影响任何操作
- `canJoinAllSpaces` + `stationary` → 切换桌面空间、进入全屏应用时视频不消失
- 多显示器时每块屏幕各建一个窗口

## 功能

- 播放任意 MP4 / MOV / M4V，硬件解码循环播放
- 菜单栏控制，不占 Dock
- 视频列表快速切换、目录内随机轮播
- 开机自动启动（LaunchAgent）
- 单实例锁，不会重复启动
- 自动生成应用图标（CoreGraphics 程序化绘制）

## 环境要求

- macOS 10.13+
- Xcode Command Line Tools（`xcode-select --install`）

## 安装

```bash
git clone https://github.com/<your-name>/DynamicWallpaper.git
cd DynamicWallpaper
./build.sh
```

`build.sh` 会依次：编译 → 生成图标 → 打包 `.app` → Ad-hoc 签名 → 安装到 `/Applications` → 注册到 LaunchServices。

## 使用

把视频放进 `~/Movies/动态壁纸/`（或任意目录），然后：

```bash
./start.sh                      # 启动，随机轮播
./start.sh "/path/to/x.mp4"     # 指定某个视频
./start.sh --dir ~/Movies/xxx   # 指定视频目录
./start.sh --list               # 列出可用视频
./start.sh --status             # 查看运行状态
./start.sh --stop               # 停止
```

也可以直接在「应用程序」里双击 **动态壁纸**。

### 菜单栏

启动后菜单栏右上角出现胶片图标：

| 项目 | 说明 |
|---|---|
| 当前: xxx.mp4 | 显示正在播放的文件 |
| 切换视频 ▸ | 视频列表，勾选当前项 |
| 下一个视频 | 手动切下一个 |
| 浏览其他视频… | 从任意位置选择 |
| 暂停播放 / 继续播放 | 停止或恢复渲染 |
| 每 30 秒随机切换 | 轮播开关 |
| 开机自动启动 | LaunchAgent 开关 |
| 关闭动态壁纸 | 退出 |

### 命令行参数

| 参数 | 说明 |
|---|---|
| `<path>` | 直接播放指定文件 |
| `--dir <path>` | 指定视频目录 |
| `--shuffle` | 目录内视频每 30 秒随机切换 |
| `--debug` | 每 2 秒输出播放进度到 stderr（排查用） |

## 性能提示

4K / 高帧率视频解码开销较大。若觉得发热或耗电快，建议转一份轻量版：

```bash
mkdir -p ~/Movies/wallpapers-1080p
for f in ~/Movies/动态壁纸/*.mp4; do
  ffmpeg -i "$f" -vf scale=1920:-2 -r 30 -c:v libx264 -crf 23 -an \
    ~/Movies/wallpapers-1080p/"$(basename "$f")"
done
```

然后 `./start.sh --dir ~/Movies/wallpapers-1080p --shuffle`。

## 开机自启

菜单栏勾选「开机自动启动」会写入：

```
~/Library/LaunchAgents/com.local.dynamicwallpaper.autostart.plist
```

取消勾选即删除并卸载。

如果当前终端环境没有 GUI 会话凭据（`launchctl bootstrap` 报 `Input/output error`），可以手动在「终端.app」执行：

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.dynamicwallpaper.autostart.plist
```

或直接等下次登录，launchd 会自动扫描该目录。

## 常见问题

**首次打开提示「无法验证开发者」**

应用为 Ad-hoc 签名，未做 Apple 公证。右键 → 打开，或：

```bash
xattr -cr /Applications/DynamicWallpaper.app
```

**桌面看不到视频**

检查是否有实例在跑：`./start.sh --status`。
用 `--debug` 启动可直接看到播放进度和 `timeControlStatus`。

**视频不显示但进程在跑**

确认视频编码是 H.264 / HEVC。可用 `ffprobe` 检查：

```bash
ffprobe -show_entries stream=codec_name,width,height "your.mp4"
```

## 项目结构

```
.
├── DynamicWallpaper.swift   # 主程序：窗口层级、播放器、菜单栏
├── makeicon.swift           # 图标生成（CoreGraphics 程序化绘制）
├── Info.plist               # bundle 配置
├── build.sh                 # 编译 + 打包 + 安装
├── start.sh                 # 启动 / 停止 / 状态
├── docs/icon.png            # README 用图标
└── LICENSE
```

构建产物（`DynamicWallpaper`、`*.app`、`AppIcon.icns` 等）均已列入 `.gitignore`，由 `build.sh` 自动生成。

## 说明

- 本项目不附带任何视频素材。请使用你有权使用的视频文件。
- 应用为 Ad-hoc 签名，适合本地使用；分发给他人的话需要自行配置开发者证书并公证。

## License

[MIT](LICENSE)
