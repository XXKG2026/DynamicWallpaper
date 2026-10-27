#!/bin/bash
# build.sh — 一键编译并打包成 /Applications/DynamicWallpaper.app
set -e

# 以脚本所在目录为项目根，避免硬编码路径
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="DynamicWallpaper"
BUNDLE_ID="com.local.dynamicwallpaper"
INSTALL_DIR="/Applications"

cd "$PROJ"

echo "▸ 1/6 编译主程序"
xcrun swiftc -O "${APP_NAME}.swift" -o "${APP_NAME}"

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
