#!/bin/bash
# 启动 / 控制 动态壁纸
#
# 用法:
#   ./start.sh                      启动（随机轮播）
#   ./start.sh /path/to/video.mp4   指定某个视频
#   ./start.sh --dir /path          指定视频目录
#   ./start.sh --debug              带播放进度日志启动
#   ./start.sh --list               列出可用视频
#   ./start.sh --stop               停止
#   ./start.sh --status             查看运行状态
#   ./start.sh --log                查看运行日志
#
# 注意：不使用 `open --args` 传参 —— macOS 26+ 上 open 会丢弃 --args，
# 应用只会拿到自身路径。改为直接启动 app 内的可执行文件。

APP="/Applications/DynamicWallpaper.app"
BIN="$APP/Contents/MacOS/DynamicWallpaper"
VIDEO_DIR="$HOME/Movies/动态壁纸"
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

# 无参数时默认随机轮播
if [ $# -eq 0 ]; then
  set -- --shuffle
fi

mkdir -p "$(dirname "$LOG")"
: > "$LOG"
nohup "$BIN" "$@" >> "$LOG" 2>&1 &
disown 2>/dev/null || true

sleep 1.5
if pgrep -f "DynamicWallpaper" > /dev/null; then
  echo "动态壁纸已启动 ✓"
  echo "菜单栏右上角胶片图标 → 切换视频 / 随机轮播 / 开机自启 / 退出"
  if grep -q "未找到视频文件" "$LOG" 2>/dev/null; then
    echo "⚠ 未找到视频文件："
    tail -3 "$LOG"
  fi
else
  echo "启动失败，日志："
  tail -10 "$LOG" 2>/dev/null
  exit 1
fi
