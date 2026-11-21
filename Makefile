# DeckOut: build and assemble the app.
#   make app                  the dev variant ("DeckOut Dev", its own config and logs), debug build
#   make app VARIANT=release  DeckOut itself, release build
#   make install-dev          the dev variant, installed to ~/Applications/DeckOut Dev.app
#   make uninstall-dev        removes DeckOut Dev from this Mac: Login Items, permissions, app, logs (keeps ~/.config/vsd-dev)
#   make test                 swift test
#   make signed VARIANT=release   Developer ID signing and the disk image (needs signing.mk; the owner's go, each time)
#   make notarize             notarises and staples that disk image (the owner's go, each time)
# m1ddc (MIT, Vendor/m1ddc) is built from source into Contents/Helpers, for monitor brightness.
# make app signs ad hoc only. Developer ID signing is make signed, with the identity named in signing.mk.

VARIANT ?= dev
ifeq ($(VARIANT),release)
  BUNDLE_ID := io.github.okoker.deckout
  APP_NAME := DeckOut
  CONFIG := release
else ifeq ($(VARIANT),dev)
  BUNDLE_ID := io.github.okoker.deckout.dev
  APP_NAME := DeckOut Dev
  CONFIG := debug
else
  $(error VARIANT must be dev or release)
endif

LABEL := $(BUNDLE_ID).agent
VERSION := $(shell cat VERSION)
BUILD := $(shell date +%y%m%d.%H%M%S)
APP := build/$(APP_NAME).app
DEV_DEST := $(HOME)/Applications/DeckOut Dev.app
DEV_ID := io.github.okoker.deckout.dev
DMG := build/DeckOut-$(VERSION).dmg
ENTITLEMENTS := Packaging/DeckOut.entitlements

# SIGN_ID (the certificate's SHA-1) and NOTARY_PROFILE. Gitignored; see signing.mk.example.
-include signing.mk
SIGN = codesign --force --timestamp -o runtime -s "$(SIGN_ID)"

.PHONY: app install-dev uninstall-dev signed notarize test

app:
	swift build -c $(CONFIG)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/Library/LaunchAgents"
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/DeckOut" "$$(swift build -c $(CONFIG) --show-bin-path)/DeckOutAgent" "$(APP)/Contents/MacOS/"
	sed -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' -e 's/@APP_NAME@/$(APP_NAME)/g' -e 's/@VERSION@/$(VERSION)/g' \
	    -e 's/@BUILD@/$(BUILD)/g' Packaging/Info.plist.in > "$(APP)/Contents/Info.plist"
	sed -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' -e 's/@LABEL@/$(LABEL)/g' Packaging/agent.plist.in \
	    > "$(APP)/Contents/Library/LaunchAgents/$(LABEL).plist"
	if [ -f Packaging/AppIcon.icns ]; then cp Packaging/AppIcon.icns "$(APP)/Contents/Resources/"; fi
	cp Packaging/Resources/Phosphor-Bold.ttf Packaging/Resources/Phosphor-Fill.ttf Packaging/Resources/phosphor-icons.json \
	    Packaging/Resources/Phosphor-LICENSE.txt "$(APP)/Contents/Resources/"
	cp LICENSE "$(APP)/Contents/Resources/DeckOut-LICENSE.txt"
	cp Vendor/m1ddc/LICENSE "$(APP)/Contents/Resources/m1ddc-LICENSE.txt"
	mkdir -p "$(APP)/Contents/Helpers" build
	clang -Wall -Werror -Wextra -fmodules -arch arm64 -mmacosx-version-min=15.0 -I Vendor/m1ddc/headers \
	    -framework CoreDisplay Vendor/m1ddc/sources/*.m -o build/m1ddc
	cp build/m1ddc "$(APP)/Contents/Helpers/m1ddc"
	codesign --force -s - -i $(BUNDLE_ID).m1ddc "$(APP)/Contents/Helpers/m1ddc"
	codesign --force -s - -i $(LABEL) "$(APP)/Contents/MacOS/DeckOutAgent"
	codesign --force -s - "$(APP)"
	scripts/check-bundle.sh "$(APP)"

# Replaces the installed copy by renaming, never by copying over a running binary (KI-008).
install-dev:
	$(MAKE) app VARIANT=dev
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/.DeckOut Dev.app.new"
	ditto "build/DeckOut Dev.app" "$(HOME)/Applications/.DeckOut Dev.app.new"
	rm -rf "$(DEV_DEST)"
	mv "$(HOME)/Applications/.DeckOut Dev.app.new" "$(DEV_DEST)"
	@echo "Installed $(DEV_DEST)"

# Leaves nothing of DeckOut Dev that can run or holds a permission. Order matters: --unregister needs the app, and
# tccutil fails with "No such bundle identifier" once the app is gone. Deleted, not binned: a binned app still opens.
uninstall-dev:
	@if [ -x "$(DEV_DEST)/Contents/MacOS/DeckOut" ]; then "$(DEV_DEST)/Contents/MacOS/DeckOut" --unregister; fi
	@# --unregister quits the same way when it fails: deleting the app then would leave its agent registered for good.
	@if launchctl print gui/$$(id -u)/$(DEV_ID).agent >/dev/null 2>&1; then \
	    echo "DeckOut Dev's agent is still registered: Stop and Remove in DeckOut Dev, quit it, then run this again" >&2; \
	    exit 1; fi
	tccutil reset Accessibility $(DEV_ID) || true
	tccutil reset AppleEvents $(DEV_ID) || true
	@for p in "$(DEV_DEST)" "$(HOME)/Applications/.DeckOut Dev.app.new" "build/DeckOut Dev.app" \
	    "$(HOME)/Library/Logs/DeckOut Dev" "$(HOME)/Library/Saved Application State/$(DEV_ID).savedState" \
	    "$(HOME)/Library/Caches/$(DEV_ID)" "$(HOME)/Library/HTTPStorages/$(DEV_ID)"; do \
	    if [ -e "$$p" ]; then rm -rf "$$p" && echo "Removed $$p"; fi; \
	done
	@if defaults delete $(DEV_ID) 2>/dev/null; then echo "Removed the $(DEV_ID) defaults"; fi
	@echo "DeckOut Dev removed. Kept: ~/.config/vsd-dev"

# Developer ID signing, inside out (m1ddc, the agent, the app), never --deep; then the disk image, signed too.
signed:
	@[ "$(VARIANT)" = release ] || { echo "make signed is for VARIANT=release only" >&2; exit 1; }
	@[ -n "$(SIGN_ID)" ] || { echo "SIGN_ID isn't set: copy signing.mk.example to signing.mk and fill it in" >&2; exit 1; }
	@[ -z "$$(git status --porcelain --untracked-files=no)" ] || { echo "commit first: a signed build is made only from a committed tree" >&2; exit 1; }
	$(MAKE) app VARIANT=release
	$(SIGN) -i $(BUNDLE_ID).m1ddc "$(APP)/Contents/Helpers/m1ddc"
	$(SIGN) -i $(LABEL) --entitlements $(ENTITLEMENTS) "$(APP)/Contents/MacOS/DeckOutAgent"
	$(SIGN) --entitlements $(ENTITLEMENTS) "$(APP)"
	scripts/check-bundle.sh --signed "$(APP)"
	rm -rf build/dmg "$(DMG)"
	mkdir -p build/dmg
	ditto "$(APP)" "build/dmg/$(APP_NAME).app"
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname DeckOut -srcfolder build/dmg -format UDZO -ov "$(DMG)"
	codesign --force --timestamp -s "$(SIGN_ID)" "$(DMG)"
	@echo "Signed $(DMG) from commit $$(git rev-parse --short HEAD)"

# A rejected submission has no ticket, so staple fails and make stops: read why with xcrun notarytool log <id>.
# spctl's origin= line (the certificate's name) is dropped from the output.
notarize:
	@[ -n "$(NOTARY_PROFILE)" ] || { echo "NOTARY_PROFILE isn't set: see signing.mk.example" >&2; exit 1; }
	@[ -f "$(DMG)" ] || { echo "no $(DMG): run make signed VARIANT=release first" >&2; exit 1; }
	xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"
	xcrun stapler validate "$(DMG)"
	@out=$$(spctl -a -t open --context context:primary-signature -v "$(DMG)" 2>&1 | grep -v '^origin='); echo "$$out"; \
	    echo "$$out" | grep -q 'source=Notarized Developer ID' || { echo "Gatekeeper doesn't see it as notarised" >&2; exit 1; }
	shasum -a 256 "$(DMG)"

test:
	swift test
