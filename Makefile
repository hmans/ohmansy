.PHONY: build test run gpu-probe iso flake-check package-iso vm-image package-factory installer-iso

APP_BUNDLE ?= dist/Ohmansy.app
FACTORY_DIR ?= dist/factory-preview

# These targets run on ARM Linux, including inside the development VM.
flake-check:
	nix flake check --no-update-lock-file

iso:
	nix build --no-update-lock-file .\#iso

vm-image:
	nix build --no-update-lock-file .\#vm-image

package-factory: vm-image
	python3 tools/release/package-factory.py --image result/*.raw.zst --output dist/factory

installer-iso:
	nix build --no-update-lock-file .\#installer-iso

package-iso: installer-iso
	python3 tools/release/package-iso.py --iso result/iso/*.iso --output dist/release

export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/module-cache

build:
	swift build --package-path app --scratch-path "$(CURDIR)/.build" --disable-sandbox -c release -debug-info-format none
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp .build/release/Ohmansy "$(APP_BUNDLE)/Contents/MacOS/Ohmansy"
	cp app/resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources/Guest"
	python3 tools/build/build-icon.py
	cp .build/app-icon/Ohmansy.icns .build/app-icon/Assets.car "$(APP_BUNDLE)/Contents/Resources/"
	cp app/legacy/guest/*.nix "$(APP_BUNDLE)/Contents/Resources/Guest/"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources/GPURuntime"
	cp app/runtime/gpu-probe.py app/runtime/factory-vm.py "$(APP_BUNDLE)/Contents/Resources/GPURuntime/"
	python3 tools/build/stage-factory.py --bundle "$(APP_BUNDLE)" --factory "$(FACTORY_DIR)"
	python3 tools/build/stage-runtime.py --bundle "$(APP_BUNDLE)"
	python3 tools/build/signing.py "$(APP_BUNDLE)" --entitlements app/resources/Ohmansy.entitlements

test:
	swift test --package-path app --scratch-path "$(CURDIR)/.build" --disable-sandbox
	python3 -m unittest discover -s tools/tests -p 'test_*.py'
	clang -fobjc-arc -mmacosx-version-min=15.0 -framework AppKit -framework QuartzCore -framework ApplicationServices -framework GameplayKit -framework Metal -framework MetalKit app/Tests/RuntimeChromeTests/main.m app/native/WelcomeCanvas.m -o .build/runtime-chrome-tests
	.build/runtime-chrome-tests

run: build
	open "$(APP_BUNDLE)"

gpu-probe:
	swift build --package-path app --scratch-path "$(CURDIR)/.build" --disable-sandbox -c release -debug-info-format none --product GraphicsProbe
	mkdir -p 'dist/ohmansy GPU test.app/Contents/MacOS' 'dist/ohmansy GPU test.app/Contents/Resources'
	cp .build/release/GraphicsProbe 'dist/ohmansy GPU test.app/Contents/MacOS/GraphicsProbe'
	cp app/resources/GraphicsProbe.plist 'dist/ohmansy GPU test.app/Contents/Info.plist'
	cp app/runtime/gpu-probe.py 'dist/ohmansy GPU test.app/Contents/Resources/'
	python3 tools/build/signing.py 'dist/ohmansy GPU test.app'
