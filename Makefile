APP := dist/Islet.app

.PHONY: build run install uninstall clean

build:
	@./scripts/build_app.sh

run: build
	@pkill -x Islet || true
	@open $(APP)
	@echo "Islet is running. Quit it from the menu bar icon."

install: build
	@pkill -x Islet || true
	@rm -rf /Applications/Islet.app
	@cp -R $(APP) /Applications/
	@open /Applications/Islet.app
	@echo "Installed to /Applications."

uninstall:
	@pkill -x Islet || true
	@rm -rf /Applications/Islet.app

clean:
	@rm -rf .build dist
