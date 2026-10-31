.PHONY: build test run

export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/module-cache

build:
	swift build --disable-sandbox -c release -debug-info-format none
	mkdir -p dist/Ohmansy.app/Contents/MacOS
	cp .build/release/Ohmansy dist/Ohmansy.app/Contents/MacOS/Ohmansy
	cp macos/Info.plist dist/Ohmansy.app/Contents/Info.plist
	mkdir -p dist/Ohmansy.app/Contents/Resources/Guest
	cp guest/*.nix dist/Ohmansy.app/Contents/Resources/Guest/
	codesign --force --sign - --entitlements macos/Ohmansy.entitlements dist/Ohmansy.app

test:
	swift test --disable-sandbox

run: build
	open dist/Ohmansy.app
