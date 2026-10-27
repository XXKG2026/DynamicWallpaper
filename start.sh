#!/bin/bash
# 启动 / 控制 动态壁纸
#
# 用法:
#   ./start.sh                      启动（随机轮播）
#   ./start.sh /path/to/video.mp4   指定某个视频
#   ./start.sh --dir /path          指定视频目录
#   ./start.sh --debug              输出播放进度到日志
#   ./start.sh --list               列出可用视频
#   ./start.sh --stop               停止
#   ./start.sh --status             查看运行状态
#   ./start.sh --log                查看运行日志
#
# 传参方式：macOS 26+ 的 `open --args` 会丢弃参数，而 nohup 启动的进程
# 会被调用方会话回收。因此先写 config.json，再用 open -a 正常启动。

set -uo pipefail

APP="/Applications/DynamicWallpaper.app"
BIN="$APP/Contents/MacOS/DynamicWallpaper"
VIDEO_DIR="$HOME/Movies/动态壁纸"
SUPPORT="$HOME/Library/Application Support/macos-video-wallpaper"
CFG="$SUPPORT/config.json"
LOG="$HOME/Library/Logs/macos-video-wallpaper.log"

case "$1" in
  --list)
    ls -1 "$VIDEO_DIR"/*.mp4 2>/dev/null | nl
    exit 0
    ;;
  --stop|stop)
    pkill -f "DynamicWallpaper" 2>/dev/null
    echo "已停止动态壁纸"
    exit 0
    ;;
  --status|status)
    if pgrep -f "DynamicWallpaper" > /dev/null; then
      echo "运行中 (PID: $(pgrep -f DynamicWallpaper | tr '\n' ' '))"
    else
      echo "未运行"
    fi
    exit 0
    ;;
  --log|log)
    [ -f "$LOG" ] && tail -20 "$LOG" || echo "暂无日志"
    exit 0
    ;;
esac

if [ ! -x "$BIN" ]; then
  echo "未找到 $APP，请先运行 ./build.sh 打包安装"
  exit 1
fi

if pgrep -f "DynamicWallpaper" > /dev/null; then
  echo "动态壁纸已在运行（更换视频请先 --stop）"
  exit 0
fi

# 解析参数
CFG_FILE=""
CFG_DIR=""
CFG_SHUFFLE=false
CFG_DEBUG=false

if [ $# -eq 0 ]; then
  CFG_DIR="$VIDEO_DIR"; CFG_SHUFFLE=true
else
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir)     CFG_DIR="${2:-}"; shift; [ -n "$CFG_DIR" ] && CFG_SHUFFLE=true ;;
      --shuffle) CFG_SHUFFLE=true ;;
      --debug)   CFG_DEBUG=true ;;
      *)
        if [ -f "$1" ]; then
          CFG_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
        else
          echo "无法识别的参数或文件不存在：$1"; exit 1
        fi
        ;;
    esac
    shift
  done
fi

# JSON 转义并写配置
json_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
mkdir -p "$SUPPORT"
{
  printf '{\n'
  [ -n "$CFG_FILE" ] && printf '  "file": "%s",\n' "$(json_escape "$CFG_FILE")"
  [ -n "$CFG_DIR" ]  && printf '  "dir": "%s",\n'  "$(json_escape "$CFG_DIR")"
  printf '  "shuffle": %s,\n' "$CFG_SHUFFLE"
  printf '  "debug": %s\n'   "$CFG_DEBUG"
  printf '}\n'
} > "$CFG"

open -a "$APP"
sleep 2.2

if ! pgrep -f "DynamicWallpaper" > /dev/null; then
  echo "启动失败，日志："
  [ -f "$LOG" ] && tail -5 "$LOG"
  exit 1
fi

if grep -q "未找到视频文件" "$LOG" 2>/dev/null; then
  echo "⚠ 未找到视频文件："
  tail -3 "$LOG"
  exit 1
fi

echo "动态壁纸已启动 ✓"
echo "菜单栏右上角胶片图标 → 切换视频 / 随机轮播 / 开机自启 / 退出"
