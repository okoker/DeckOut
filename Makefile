# DeckOut: build and assemble the app.
#   make app                  the dev variant ("DeckOut Dev", its own config and logs), debug build
#   make app VARIANT=release  DeckOut itself, release build
#   make install-dev          the dev variant, installed to ~/Applications/DeckOut Dev.app
#   make test                 swift test
# Signing here is ad hoc only. Signing with a certificate is a separate step, run with the owner's go.

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

.PHONY: app install-dev test

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

test:
	swift test
