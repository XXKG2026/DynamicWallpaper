#!/bin/bash
# make-skill.sh — 从仓库源码生成完整可分发的 skill 包
#
# skill/ 目录只存 SKILL.md 和 scripts/，app 源码复用仓库根目录的那份，
# 由本脚本在打包时复制进去，避免同一份代码在仓库里存两遍。
#
# 用法:
#   ./make-skill.sh              生成 dist/macos-video-wallpaper.zip
#   ./make-skill.sh /path/out    指定输出目录

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$ROOT/dist}"
NAME="macos-video-wallpaper"

# 下面会 cd 到临时目录，相对路径会失效，先固定成绝对路径
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

SKILL="$STAGE/$NAME"
mkdir -p "$SKILL/assets/src" "$SKILL/scripts"

cp "$ROOT/skill/SKILL.md"        "$SKILL/SKILL.md"
cp "$ROOT/skill/scripts/"*.sh    "$SKILL/scripts/"

# app 源码直接取自仓库根目录
cp "$ROOT/DynamicWallpaper.swift" "$ROOT/makeicon.swift" \
   "$ROOT/Info.plist" "$ROOT/build.sh" "$SKILL/assets/src/"

chmod +x "$SKILL/scripts/"*.sh "$SKILL/assets/src/build.sh"

mkdir -p "$OUT"
rm -f "$OUT/$NAME.zip"
( cd "$STAGE" && zip -qr "$OUT/$NAME.zip" "$NAME" )

echo "✓ 已生成 $OUT/$NAME.zip"
unzip -l "$OUT/$NAME.zip" | awk 'NR>3 && $4 != "" {printf "  %s\n", $4}'
