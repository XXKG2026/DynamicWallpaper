---
name: macos-video-wallpaper
description: This skill should be used when the user wants to set a video (MP4/MOV/M4V) as their macOS desktop wallpaper, or manage an existing video wallpaper — e.g. "把这段视频设为壁纸", "用这个视频当桌面背景", "动态壁纸", "视频壁纸", "live wallpaper", "video wallpaper", "停止动态壁纸", "换个壁纸". It installs the companion native app if needed, then starts, stops, lists, and switches wallpaper videos. macOS only.
agent_created: true
---

# macOS 视频壁纸

## 概述

macOS 系统设置只支持静态图片，没有视频壁纸选项。本技能通过一个原生 Swift 应用实现：创建一个窗口层级位于桌面壁纸图片与桌面图标之间的全屏窗口播放视频，因此桌面图标和所有应用窗口正常覆盖其上，鼠标点击直接穿透。

技能自带完整源码，可在任意 Mac 上编译安装。

## 工作流程

按顺序执行，每步根据输出决定是否继续。

### 第 1 步：确保应用已安装

```bash
bash scripts/install.sh
```

幂等操作。已安装时立即返回 `OK:` 并跳过编译。输出约定：

| 前缀 | 含义 | 后续动作 |
|---|---|---|
| `OK:` | 成功 | 继续 |
| `INFO:` | 进度信息 | 继续 |
| `ERR:` | 失败 | 停止，把原文反馈给用户 |

常见失败：缺少 Xcode Command Line Tools。此时提示用户执行 `xcode-select --install`，不要尝试其他替代方案。

### 第 2 步：确定要播放的视频

用户已指定文件时直接进入第 3 步。未指定时，先列出可用视频：

```bash
bash scripts/wallpaper.sh list
```

脚本会自动探测 `~/Movies/动态壁纸`、`~/Movies/Wallpapers`、`~/Movies/wallpapers` 中第一个含视频的目录。若全部不存在，返回 `ERR:`，此时向用户询问视频所在目录，再执行 `bash scripts/wallpaper.sh list /path/to/dir`。

将列表呈现给用户并让其选择，不要替用户随机决定。

### 第 3 步：启动

```bash
# 播放指定视频
bash scripts/wallpaper.sh start "/path/to/video.mp4"

# 目录内视频每 30 秒随机切换
bash scripts/wallpaper.sh start --dir "/path/to/dir"

# 无参数：自动探测目录并随机轮播
bash scripts/wallpaper.sh start
```

应用有单实例锁。已在运行时 `start` 会返回 `OK: 动态壁纸已在运行`，需先 `stop` 才能更换视频。

## 命令参考

| 命令 | 说明 |
|---|---|
| `scripts/install.sh [--force]` | 编译并安装应用；`--force` 强制重装 |
| `scripts/wallpaper.sh start [path\|--dir D\|--shuffle]` | 启动播放 |
| `scripts/wallpaper.sh stop` | 停止 |
| `scripts/wallpaper.sh status` | 查看是否运行及 PID |
| `scripts/wallpaper.sh log` | 查看运行日志（含 `--debug` 输出） |
| `scripts/wallpaper.sh list [dir]` | 列出可用视频 |
| `scripts/wallpaper.sh install [--force]` | 转发到 install.sh |

## 安装位置

| 项目 | 路径 |
|---|---|
| 应用 | `/Applications/DynamicWallpaper.app`（不可写时回退 `~/Applications`） |
| 编译工作区 | `~/Library/Application Support/macos-video-wallpaper/src/` |
| 启动配置 | `~/Library/Application Support/macos-video-wallpaper/config.json` |
| 运行日志 | `~/Library/Logs/macos-video-wallpaper.log` |
| 视频（默认探测） | `~/Movies/动态壁纸`、`~/Movies/Wallpapers` |

应用为 Ad-hoc 签名，`LSUIElement = true`（不占 Dock，仅菜单栏胶片图标）。菜单栏可切换视频、暂停、开关随机轮播、开关开机自启。

## 传参机制（重要）

`wallpaper.sh start` 不通过命令行参数传递选择，而是先写 `config.json` 再 `open -a` 启动，应用启动时读取该文件：

```json
{
  "file": "/path/to/video.mp4",   // 可选，指定单个视频
  "dir": "/path/to/dir",          // 可选，指定目录
  "shuffle": true,
  "debug": false
}
```

原因见「注意事项」。优先级：命令行参数 > config.json > 内置默认值，因此 LaunchAgent 里写的 `--shuffle` 仍然生效。

## 验证播放是否真的在进行

`status` 只说明进程存活，不代表画面在动。需要确认时，带 `--debug` 启动，它会每 2 秒把播放进度写进日志：

```bash
bash scripts/wallpaper.sh stop
bash scripts/wallpaper.sh start --debug --dir "$HOME/Movies/动态壁纸"
sleep 6
bash scripts/wallpaper.sh log
```

预期日志（`t` 持续增长、`status=playing`、`rate=1.0`）：

```
[debug] t=1.76s status=playing rate=1.0
[debug] t=3.76s status=playing rate=1.0
[debug] t=5.76s status=playing rate=1.0
```

确认后执行 `bash scripts/wallpaper.sh stop`，再用不带 `--debug` 的方式启动，避免持续写日志。

## 故障排查

**启动后桌面看不到视频**

先用 `--debug` 确认播放状态。若显示 `playing` 但画面无变化，通常是窗口层级未生效——检查应用是否从 `/Applications` 正常启动，而非在受限沙箱中运行。

**视频不显示但进程在跑**

确认编码为 H.264 或 HEVC：

```bash
ffprobe -show_entries stream=codec_name,width,height "video.mp4"
```

**提示「无法验证开发者」**

Ad-hoc 签名未做 Apple 公证。执行：

```bash
xattr -cr /Applications/DynamicWallpaper.app
```

**4K 视频导致发热或耗电快**

4K / 高帧率解码开销大。建议转轻量版后播放该目录：

```bash
mkdir -p ~/Movies/wallpapers-1080p
for f in ~/Movies/动态壁纸/*.mp4; do
  ffmpeg -i "$f" -vf scale=1920:-2 -r 30 -c:v libx264 -crf 23 -an \
    ~/Movies/wallpapers-1080p/"$(basename "$f")"
done
```

然后 `bash scripts/wallpaper.sh start --dir ~/Movies/wallpapers-1080p`。

## 注意事项

- 仅支持 macOS 10.13+，需要 Xcode Command Line Tools
- 不附带任何视频素材，使用用户自己的文件
- **不要用 `open -a ... --args` 传参，也不要 `nohup` 直接启动二进制**。这是本技能踩过的两个坑：
  1. macOS 26+ 上 `open` 会丢弃 `--args`（`-a`/`-b`/`-n`/等号形式全部实测失效），应用只能拿到自身路径
  2. `nohup ... &` 启动的进程会在调用方会话结束时被回收，表现为 `start` 报成功但壁纸立刻消失

  最终方案：写 `config.json` + `open -a` 正常启动（进程由 launchd 托管，能存活），应用读配置决定播放内容
- 应用同时把日志写入 `~/Library/Logs/macos-video-wallpaper.log`，因为 `open -a` 启动时 stderr 不可见。`wallpaper.sh log` 可查看
- 开机自启由应用内菜单控制，写入 `~/Library/LaunchAgents/com.local.dynamicwallpaper.autostart.plist`。在缺少 GUI 会话凭据的终端里 `launchctl bootstrap` 会报 `Input/output error`，这属正常现象，不影响下次登录自动加载
- 源码位于 `assets/src/`，修改后重新执行 `install.sh --force` 生效
