.PHONY: build test run gpu-probe

export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/module-cache

build:
	swift build --disable-sandbox -c release -debug-info-format none
	mkdir -p dist/Ohmansy.app/Contents/MacOS
	cp .build/release/Ohmansy dist/Ohmansy.app/Contents/MacOS/Ohmansy
	cp macos/Info.plist dist/Ohmansy.app/Contents/Info.plist
	mkdir -p dist/Ohmansy.app/Contents/Resources/Guest
	python3 scripts/build-icon.py
	cp .build/app-icon/Ohmansy.icns .build/app-icon/Assets.car dist/Ohmansy.app/Contents/Resources/
	cp guest/*.nix dist/Ohmansy.app/Contents/Resources/Guest/
	mkdir -p dist/Ohmansy.app/Contents/Resources/GPURuntime
	cp scripts/gpu-probe.py dist/Ohmansy.app/Contents/Resources/GPURuntime/
	python3 scripts/stage-runtime.py
	python3 scripts/signing.py dist/Ohmansy.app --entitlements macos/Ohmansy.entitlements

test:
	swift test --disable-sandbox
	python3 -m unittest discover -s scripts -p 'test_*.py'
	clang -fobjc-arc -mmacosx-version-min=15.0 -framework AppKit -framework QuartzCore -framework ApplicationServices -framework GameplayKit -framework Metal -framework MetalKit Tests/RuntimeChromeTests/main.m macos/WelcomeCanvas.m -o .build/runtime-chrome-tests
	.build/runtime-chrome-tests

run: build
	open dist/Ohmansy.app

gpu-probe:
	swift build --disable-sandbox -c release -debug-info-format none --product GraphicsProbe
	mkdir -p 'dist/ohmansy GPU test.app/Contents/MacOS' 'dist/ohmansy GPU test.app/Contents/Resources'
	cp .build/release/GraphicsProbe 'dist/ohmansy GPU test.app/Contents/MacOS/GraphicsProbe'
	cp macos/GraphicsProbe.plist 'dist/ohmansy GPU test.app/Contents/Info.plist'
	cp scripts/gpu-probe.py 'dist/ohmansy GPU test.app/Contents/Resources/'
	python3 scripts/signing.py 'dist/ohmansy GPU test.app'
