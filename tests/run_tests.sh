#!/bin/bash
# 在 macOS 上编译并运行插件的核心逻辑自测（不需要 iOS 设备）
set -e

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/.build"
mkdir -p "$OUT"

echo "==> 编译测试程序 (macOS)"
CORE_SOURCES=(
  Sources/ZHNACommon.m
  Sources/ZHNAConfig.m
  Sources/ZHNARules.m
  Sources/ZHNAJSONFilter.m
  Sources/ZHNASwizzle.m
)

clang -fobjc-arc -fmodules -Wall \
  -ISources \
  -framework Foundation \
  "${CORE_SOURCES[@]}" tests/ZHNATests.m \
  -o "$OUT/zhna_tests"

echo "==> 运行"
"$OUT/zhna_tests"

echo
echo "==> 语法检查全部源码（含只在 iOS 上运行的部分）"
for f in Sources/*.m; do
  clang -fobjc-arc -fsyntax-only -Wall -ISources "$f" && echo "  ✓ $f"
done

echo
echo "全部检查通过。"
