SHELL := /bin/bash
.DEFAULT_GOAL := build

.PHONY: build run app dmg

build:
	swift build --product IsleKit

app:
	./scripts/build-native.sh

run: app
	open dist/IsleKit.app

dmg: app
	set -eu; stage=$$(mktemp -d); trap 'rm -rf "$$stage"' EXIT; \
	ditto dist/IsleKit.app "$$stage/IsleKit.app"; ln -s /Applications "$$stage/Applications"; \
	hdiutil create -ov -format UDZO -volname IsleKit -srcfolder "$$stage" dist/IsleKit.dmg
