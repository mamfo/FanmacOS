APP := build/FanmacOS.app

.PHONY: build run dump icon dist install uninstall clean

build:
	./build.sh

icon:
	./scripts/build-icon.sh

run: build
	open $(APP)

dump: build
	$(APP)/Contents/MacOS/FanmacOS --dump

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
