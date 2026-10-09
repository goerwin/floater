SHELL := /bin/bash

VERSION ?= 0.1.0
CONFIGURATION ?= release
BUILD_DIR ?= build
DIST_DIR ?= dist
APP_BUNDLE := $(BUILD_DIR)/Floater.app
SPM_SCRATCH_DIR := .build/SwiftPM
SPM_CACHE_DIR := .build/spm-cache
SPM_CONFIG_DIR := .build/spm-config
SPM_SECURITY_DIR := .build/spm-security
MODULE_CACHE_DIR := .build/module-cache
CODE_SIGNING_IDENTITY ?=
FLOATER_PROMPT ?=
FLOATER_INPUT ?=
FLOATER_TITLE ?=

export FLOATER_PROMPT FLOATER_INPUT FLOATER_TITLE

SWIFT_ENV = SWIFTPM_MODULECACHE_OVERRIDE="$(CURDIR)/$(MODULE_CACHE_DIR)"
SWIFTPM_ARGS = --package-path "$(CURDIR)" \
	--scratch-path "$(CURDIR)/$(SPM_SCRATCH_DIR)" \
	--cache-path "$(CURDIR)/$(SPM_CACHE_DIR)" \
	--config-path "$(CURDIR)/$(SPM_CONFIG_DIR)" \
	--security-path "$(CURDIR)/$(SPM_SECURITY_DIR)" \
	--manifest-cache local \
	--disable-sandbox

.PHONY: help test test-app build dev install release release-patch release-minor release-major clean

help:
	@printf '%s\n' \
		'make test          Run the Swift test suite' \
		'make test-app      Rebuild and smoke test the app through macOS' \
		'make build         Build Floater.app' \
		'make dev           Rebuild and launch Floater (optional FLOATER_PROMPT, FLOATER_INPUT, FLOATER_TITLE)' \
		'make install       Install Floater.app in /Applications' \
		'make release       Build a versioned release DMG' \
		'make release-patch Create and push the next patch release tag' \
		'make release-minor Create and push the next minor release tag' \
		'make release-major Create and push the next major release tag'

test-app:
	FLOATER_VERSION="$(VERSION)" bash Scripts/test-app.sh

test:
	@mkdir -p "$(SPM_SCRATCH_DIR)" "$(SPM_CACHE_DIR)" "$(SPM_CONFIG_DIR)" "$(SPM_SECURITY_DIR)" "$(MODULE_CACHE_DIR)"
	$(SWIFT_ENV) swift test $(SWIFTPM_ARGS)

build:
	FLOATER_VERSION="$(VERSION)" Scripts/build-app.sh "$(CONFIGURATION)"

dev:
	FLOATER_VERSION="$(VERSION)" bash Scripts/dev.sh

install:
	FLOATER_VERSION="$(VERSION)" Scripts/build-app.sh release
	sudo ditto "$(APP_BUNDLE)" "/Applications/Floater.app"
	@printf 'Installed Floater.app to /Applications/Floater.app\n'

release:
	@mkdir -p "$(DIST_DIR)"
	FLOATER_VERSION="$(VERSION)" CODE_SIGNING_IDENTITY="$(CODE_SIGNING_IDENTITY)" Scripts/build-app.sh release
	DIST_DIR="$(DIST_DIR)" Scripts/make-dmg.sh "$(APP_BUNDLE)"
	cd "$(DIST_DIR)" && shasum -a 256 "Floater-$(VERSION).dmg" > "Floater-$(VERSION)-SHA256SUMS"

release-patch:
	Scripts/release.sh patch

release-minor:
	Scripts/release.sh minor

release-major:
	Scripts/release.sh major

clean:
	rm -rf .build "$(BUILD_DIR)" "$(DIST_DIR)"
