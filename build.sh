#!/bin/bash
# build.sh — 一键编译并打包成 /Applications/DynamicWallpaper.app
set -e

# 以脚本所在目录为项目根，避免硬编码路径
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DynamicWallpaper"
BUNDLE_ID="com.local.dynamicwallpaper"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"   # 可用环境变量覆盖，如 ~/Applications
UNIVERSAL="${UNIVERSAL:-0}"                   # =1 时编译 arm64 + x86_64 通用二进制（发布用）

cd "$PROJ"

echo "▸ 1/6 编译主程序"
if [ "$UNIVERSAL" = "1" ]; then
  # 通用二进制：Apple Silicon 与 Intel 都能原生运行
  # 注意：代码用到 UTType / allowedContentTypes，最低 macOS 11.0，不是 10.13
  for arch in arm64 x86_64; do
    xcrun swiftc -O -target "${arch}-apple-macos11.0" "${APP_NAME}.swift" -o "${APP_NAME}-${arch}"
  done
  xcrun lipo -create -output "${APP_NAME}" "${APP_NAME}-arm64" "${APP_NAME}-x86_64"
  rm -f "${APP_NAME}-arm64" "${APP_NAME}-x86_64"
  echo "  通用二进制: $(xcrun lipo -archs "${APP_NAME}")"
else
  xcrun swiftc -O "${APP_NAME}.swift" -o "${APP_NAME}"
fi

echo "▸ 2/6 生成图标"
if [ ! -f AppIcon.icns ] || [ "${APP_NAME}.swift" -nt AppIcon.icns ]; then
  xcrun swiftc -O makeicon.swift -o makeicon
  ./makeicon icon_1024.png
  rm -rf AppIcon.iconset && mkdir -p AppIcon.iconset
  for s in 16 32 64 128 256 512; do
    sips -z $s $s icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d icon_1024.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  echo "  图标已重建"
else
  echo "  图标已存在，跳过"
fi

echo "▸ 3/6 构建 .app 结构"
rm -rf "${APP_NAME}.app"
mkdir -p "${APP_NAME}.app/Contents/MacOS" "${APP_NAME}.app/Contents/Resources"
cp "${APP_NAME}"            "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
cp Info.plist               "${APP_NAME}.app/Contents/Info.plist"
cp AppIcon.icns             "${APP_NAME}.app/Contents/Resources/AppIcon.icns"
printf 'APPL????'         > "${APP_NAME}.app/Contents/PkgInfo"
chmod +x                    "${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

echo "▸ 4/6 Ad-hoc 签名"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "${APP_NAME}.app"

echo "▸ 5/6 安装到 ${INSTALL_DIR}"
pkill -f "$APP_NAME" 2>/dev/null || true
sleep 0.5
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_NAME}.app" "${INSTALL_DIR}/"
# 从 exFAT 等不支持 Unix 权限的文件系统复制时，权限会变成 700，这里归一化为标准值
chmod -R u+rwX,go+rX "${INSTALL_DIR}/${APP_NAME}.app"
chmod +x "${INSTALL_DIR}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
xattr -cr "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true
codesign -v "${INSTALL_DIR}/${APP_NAME}.app"

echo "▸ 6/6 注册到 LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${INSTALL_DIR}/${APP_NAME}.app"

echo ""
echo "✓ 完成: ${INSTALL_DIR}/${APP_NAME}.app"
du -sh "${INSTALL_DIR}/${APP_NAME}.app"
