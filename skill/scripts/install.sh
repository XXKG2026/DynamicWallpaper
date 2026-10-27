#!/bin/bash
# install.sh — 编译并安装 动态壁纸 应用到本机
#
# 用法:
#   install.sh            已安装则跳过
#   install.sh --force    强制重新编译安装
#
# 输出以 "OK:" / "ERR:" 开头，便于调用方解析。

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SKILL_DIR/assets/src"
WORK="$HOME/Library/Application Support/macos-video-wallpaper/src"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

# 解析已安装位置
find_app() {
  for d in "/Applications" "$HOME/Applications"; do
    if [ -d "$d/DynamicWallpaper.app" ]; then
      echo "$d/DynamicWallpaper.app"
      return 0
    fi
  done
  return 1
}

# 1. 平台检查
if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERR: 此技能仅支持 macOS"
  exit 1
fi

# 2. 已安装则直接返回
if APP="$(find_app)" && [ "$FORCE" -eq 0 ]; then
  echo "OK: 已安装 ${APP}（如需重装请加 --force）"
  exit 0
fi

# 3. 编译工具链检查
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "ERR: 未找到 swiftc，请先安装 Xcode Command Line Tools：xcode-select --install"
  exit 1
fi

# 4. 选择安装目录（非管理员回退到 ~/Applications）
INSTALL_DIR="/Applications"
if ! [ -w "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
  echo "INFO: /Applications 不可写，改装到 $INSTALL_DIR"
fi

# 5. 复制源码到稳定位置并编译
mkdir -p "$WORK"
rsync -a --exclude='.DS_Store' "$SRC/" "$WORK/" || {
  echo "ERR: 复制源码失败"
  exit 1
}

echo "INFO: 正在编译（首次约 10-20 秒）..."
if ! ( cd "$WORK" && INSTALL_DIR="$INSTALL_DIR" bash build.sh ) 2>&1 | tail -20; then
  echo "ERR: 编译或安装失败"
  exit 1
fi

APP="$(find_app)" || true
if [ -z "${APP:-}" ] || [ ! -d "$APP" ]; then
  echo "ERR: 安装后未找到 .app"
  exit 1
fi

if ! codesign -v "$APP" 2>/dev/null; then
  echo "ERR: 代码签名校验失败"
  exit 1
fi

echo "OK: 已安装 $APP"
