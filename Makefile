# Xcode isn't installed on this Mac, so the .app bundle is assembled by hand
# from a SwiftPM build rather than produced by xcodebuild.

APP     := Dusk.app
BUILD   := .build/release
CONTENT := $(APP)/Contents

.PHONY: all check build bundle sign install run stop clean

all: install

# Verification runs as a plain executable; XCTest ships with Xcode.
check:
	swift run DuskCheck

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(CONTENT)/MacOS $(CONTENT)/Resources
	cp $(BUILD)/Dusk $(CONTENT)/MacOS/Dusk
	cp Resources/Info.plist $(CONTENT)/Info.plist
	cp scripts/install-sudoers.sh $(CONTENT)/Resources/install-sudoers.sh

# Dusk needs no TCC permissions — brightness and pmset both work without them —
# so an ad-hoc signature is enough and no certificate has to be kept around.
sign: bundle
	codesign --force --sign - --identifier parkchanbin.Dusk $(APP)

install: check sign
	@pkill -x Dusk || true
	rm -rf /Applications/$(APP)
	cp -R $(APP) /Applications/$(APP)
	@echo "installed /Applications/$(APP)"

run: install
	open /Applications/$(APP)

stop:
	@pkill -x Dusk || true

clean:
	rm -rf .build $(APP)
