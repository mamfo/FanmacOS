APP := build/FanmacOS.app

.PHONY: build test run dump icon dist install uninstall clean

build:
	./build.sh

icon:
	./scripts/build-icon.sh

run: build
	open $(APP)

dump: build
	$(APP)/Contents/MacOS/FanmacOS --dump

test: build
	swiftc -swift-version 5 -target arm64-apple-macos13.0 \
		Sources/SMC.swift Sources/FanControl.swift Sources/FanControlService.swift \
		Sources/Preferences.swift Sources/AppInfo.swift Sources/Models.swift \
		Sources/Formatting.swift Sources/NetworkMonitor.swift Sources/DiskMonitor.swift Sources/PowerMonitor.swift \
		Sources/MetricsHistory.swift Sources/BarPreset.swift Sources/FanCurve.swift Sources/FanProfile.swift Sources/AlertManager.swift Sources/MenuViews.swift Sources/FanWindow.swift Sources/UpdateService.swift \
		Tests/main.swift -o build/FanmacOSTests
	./build/FanmacOSTests

dist: build
	./scripts/make-dist.sh

install: build
	rm -rf /Applications/FanmacOS.app
	cp -R $(APP) /Applications/
	open /Applications/FanmacOS.app
	@echo "Instalado em /Applications/FanmacOS.app"

uninstall:
	rm -rf /Applications/FanmacOS.app
	@echo "Removido de /Applications"

clean:
	rm -rf build
