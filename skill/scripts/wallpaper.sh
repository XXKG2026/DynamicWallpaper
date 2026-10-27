#!/bin/bash
# wallpaper.sh — 控制 macOS 动态壁纸
#
# 用法:
#   wallpaper.sh start                   启动（自动选视频目录，随机轮播）
#   wallpaper.sh start /path/to/a.mp4    播放指定视频
#   wallpaper.sh start --dir /path       指定视频目录（自动开启轮播）
#   wallpaper.sh start --shuffle         目录内随机轮播
#   wallpaper.sh start --debug           输出播放进度到日志
#   wallpaper.sh stop                    停止
#   wallpaper.sh status                  查看状态
#   wallpaper.sh log                     查看运行日志
#   wallpaper.sh list [dir]              列出可用视频
#   wallpaper.sh install [--force]       安装/重装应用
#
# 输出以 OK: / ERR: / INFO: 开头，便于解析。
#
# 传参方式说明：
#   macOS 26+ 的 `open -a <app> --args` 会丢弃所有参数（应用只拿到自身路径），
#   而直接 nohup 启动的进程会在调用方会话结束时被回收。
#   因此：先把参数写成 config.json，再用 `open -a` 正常启动，
#   应用启动时读取该配置文件。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT="$HOME/Library/Application Support/macos-video-wallpaper"
CFG="$SUPPORT/config.json"
LOG="$HOME/Library/Logs/macos-video-wallpaper.log"
CMD="${1:-}"
shift 2>/dev/null || true

CANDIDATE_DIRS=(
  "$HOME/Movies/动态壁纸"
  "$HOME/Movies/Wallpapers"
  "$HOME/Movies/wallpapers"
)

find_app() {
  for d in "/Applications" "$HOME/Applications"; do
    if [ -d "$d/DynamicWallpaper.app" ]; then
      echo "$d/DynamicWallpaper.app"
      return 0
    fi
  done
  return 1
}

detect_dir() {
  for d in "${CANDIDATE_DIRS[@]}"; do
    if [ -d "$d" ] && [ -n "$(find "$d" -maxdepth 1 -name '*.mp4' -print -quit 2>/dev/null)" ]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

is_running() { pgrep -f "DynamicWallpaper" >/dev/null 2>&1; }

# JSON 字符串转义（反斜杠、双引号）
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

write_config() {
  local file="$1" dir="$2" shuffle="$3" debug="$4"
  mkdir -p "$SUPPORT"
  {
    printf '{\n'
    [ -n "$file" ] && printf '  "file": "%s",\n' "$(json_escape "$file")"
    [ -n "$dir" ]  && printf '  "dir": "%s",\n'  "$(json_escape "$dir")"
    printf '  "shuffle": %s,\n' "$shuffle"
    printf '  "debug": %s\n'   "$debug"
    printf '}\n'
  } > "$CFG"
}

case "$CMD" in
  install)
    exec "$SCRIPT_DIR/install.sh" "$@"
    ;;

  start)
    APP="$(find_app)" || {
      echo "ERR: 应用未安装，请先运行 install.sh"
      exit 1
    }

    if is_running; then
      echo "OK: 动态壁纸已在运行（如需更换视频先执行 stop）"
      exit 0
    fi

    # 解析参数
    CFG_FILE=""
    CFG_DIR_PATH=""
    CFG_SHUFFLE=false
    CFG_DEBUG=false

    if [ $# -eq 0 ]; then
      if DIR="$(detect_dir)"; then
        CFG_DIR_PATH="$DIR"; CFG_SHUFFLE=true
        echo "INFO: 使用视频目录 $DIR"
      else
        CFG_SHUFFLE=true
        echo "INFO: 使用应用默认视频目录"
      fi
    else
      i=1
      while [ $i -le $# ]; do
        a="${!i}"
        i=$((i + 1))
        case "$a" in
          --dir)
            CFG_DIR_PATH="${!i}"; i=$((i + 1))
            [ -n "$CFG_DIR_PATH" ] && CFG_SHUFFLE=true
            ;;
          --shuffle) CFG_SHUFFLE=true ;;
          --debug)   CFG_DEBUG=true ;;
          *)
            if [ -f "$a" ]; then
              CFG_FILE="$(cd "$(dirname "$a")" && pwd)/$(basename "$a")"
            else
              echo "ERR: 无法识别的参数或文件不存在：$a"
              exit 1
            fi
            ;;
        esac
      done
    fi

    write_config "$CFG_FILE" "$CFG_DIR_PATH" "$CFG_SHUFFLE" "$CFG_DEBUG"

    if [ -n "$CFG_FILE" ]; then
      TARGET_DESC="文件 $(basename "$CFG_FILE")"
    else
      TARGET_DESC="目录 ${CFG_DIR_PATH:-默认}"
    fi
    echo "INFO: 配置 ${TARGET_DESC} shuffle=${CFG_SHUFFLE} debug=${CFG_DEBUG}"

    open -a "$APP"
    sleep 2.2

    if ! is_running; then
      echo "ERR: 启动失败"
      [ -f "$LOG" ] && tail -5 "$LOG"
      exit 1
    fi

    if grep -q "未找到视频文件" "$LOG" 2>/dev/null; then
      echo "ERR: 未找到视频文件"
      tail -3 "$LOG"
      exit 1
    fi

    echo "OK: 动态壁纸已启动"
    ;;

  stop)
    if is_running; then
      pkill -f "DynamicWallpaper" 2>/dev/null
      sleep 0.8
      echo "OK: 已停止"
    else
      echo "OK: 本来就没在运行"
    fi
    ;;

  status)
    if is_running; then
      echo "OK: 运行中"
      echo "INFO: PID $(pgrep -f DynamicWallpaper | tr '\n' ' ')"
      APP="$(find_app)" && echo "INFO: 应用 $APP"
    else
      echo "OK: 未运行"
    fi
    ;;

  log)
    if [ -f "$LOG" ]; then
      echo "INFO: $LOG"
      tail -20 "$LOG"
    else
      echo "INFO: 暂无日志"
    fi
    ;;

  list)
    DIR="${1:-}"
    if [ -z "$DIR" ]; then
      DIR="$(detect_dir)" || {
        echo "ERR: 未找到含视频的目录，请指定：wallpaper.sh list /path/to/dir"
        exit 1
      }
    fi
    if [ ! -d "$DIR" ]; then
      echo "ERR: 目录不存在：$DIR"
      exit 1
    fi
    COUNT=0
    while IFS= read -r f; do
      COUNT=$((COUNT + 1))
      printf '%d\t%s\n' "$COUNT" "$(basename "$f")"
    done < <(find "$DIR" -maxdepth 1 \( -name '*.mp4' -o -name '*.mov' -o -name '*.m4v' \) ! -name '._*' 2>/dev/null | sort)
    if [ "$COUNT" -eq 0 ]; then
      echo "ERR: $DIR 下没有视频文件"
      exit 1
    fi
    echo "INFO: 共 $COUNT 个，目录 $DIR"
    ;;

  *)
    echo "ERR: 未知命令 '${CMD}'"
    echo "可用命令: start | stop | status | log | list | install"
    exit 1
    ;;
esac
