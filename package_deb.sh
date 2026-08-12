#!/bin/bash
#
# 将编译好的 dylib 打包成 .deb（供越狱环境用 Sileo/Zebra 安装）。
# 前置：build/ZhihuNoAds.dylib 已存在；本机需安装 dpkg（macOS: brew install dpkg）。
#
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
# rootless 布局：iOS 15+（含 iOS 16 / Dopamine）的注入目录是 /var/jb/Library/TweakInject
DST="$ROOT/layout/var/jb/Library/TweakInject"

mkdir -p "$DST"
cp "$BUILD/ZhihuNoAds.dylib" "$DST/ZhihuNoAds.dylib"
cp "$ROOT/ZhihuNoAds.plist" "$DST/ZhihuNoAds.plist"

mkdir -p "$ROOT/build"
dpkg-deb --build --root-owner-group "$ROOT/layout" "$ROOT/build/ZhihuNoAds.deb"

echo ""
echo "✅ 已生成: build/ZhihuNoAds.deb"
echo "   dylib 路径(供巨魔注入): build/ZhihuNoAds.dylib"
