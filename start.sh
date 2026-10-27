#!/bin/bash
# 启动 / 控制 动态壁纸
#
# 用法:
#   ./start.sh                      启动（随机轮播）
#   ./start.sh /path/to/video.mp4   指定某个视频
#   ./start.sh --dir /path          指定视频目录
#   ./start.sh --list               列出可用视频
#   ./start.sh --stop               停止
#   ./start.sh --status             查看运行状态

APP="/Applications/DynamicWallpaper.app"
BIN="$APP/Contents/MacOS/DynamicWallpaper"
VIDEO_DIR="$HOME/Movies/动态壁纸"

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
esac

if [ ! -x "$BIN" ]; then
  echo "未找到 $APP，请先运行 ./build.sh 打包安装"
  exit 1
fi

if pgrep -f "DynamicWallpaper" > /dev/null; then
  echo "动态壁纸已在运行"
  exit 0
fi

if [ $# -eq 0 ]; then
  open -a "$APP" --args --shuffle
else
  open -a "$APP" --args "$@"
fi

sleep 1.5
if pgrep -f "DynamicWallpaper" > /dev/null; then
  echo "动态壁纸已启动 ✓"
  echo "菜单栏右上角胶片图标 → 切换视频 / 随机轮播 / 开机自启 / 退出"
else
  echo "启动失败，尝试直接运行以查看错误："
  "$BIN" "$@"
fi
