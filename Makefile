# ZhihuNoAds 构建脚本
# 不需要 Theos。直接用 clang + iOS SDK 编译成 dylib。
# 说明：本地若只有 Xcode Command Line Tools（没有完整的 iPhoneOS SDK）是无法编译的，
#       这种情况请用仓库里的 GitHub Actions 云端一键编译（见 README）。

XCODE_SDK_PATH := $(shell xcodebuild -sdk iphoneos -version Path 2>/dev/null)
CC ?= clang
ARCH ?= arm64
TARGET_MIN ?= 14.0

SRC := $(wildcard Sources/*.m)
OUT := build/ZhihuNoAds.dylib

CFLAGS := -dynamiclib -arch $(ARCH) -target $(ARCH)-apple-ios$(TARGET_MIN) -isysroot $(XCODE_SDK_PATH) -fobjc-arc -fmodules -framework Foundation -Os

.PHONY: all codesign package clean

all: $(OUT)

$(OUT): $(SRC)
	mkdir -p build
	$(CC) $(CFLAGS) $(SRC) -o $(OUT)

codesign: $(OUT)
	@which ldid >/dev/null 2>&1 && ldid -S $(OUT) || codesign --force --sign - $(OUT)
	@echo "已签名: $(OUT)"

package: codesign
	bash package_deb.sh

clean:
	rm -rf build
