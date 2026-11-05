SHELL := /bin/bash

PROJECT := Kotoba.xcodeproj
SCHEME := PLaMoTranslate
DERIVED_DATA := $(CURDIR)/.build/DerivedData

# Evaluated lazily: only test targets need a booted iPhone simulator.
SIMULATOR = $(shell ./scripts/ci/select-simulator.sh 2>/dev/null)

.PHONY: help bootstrap generate fetch-llama build-for-testing test test-unit test-ui build-device clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'

bootstrap: fetch-llama ## Fetch llama.xcframework (device) and check tooling
	@command -v xcodegen >/dev/null || echo "xcodegen is missing: brew install xcodegen"
	@echo "Next: make generate && open $(PROJECT)"

generate: ## Generate Kotoba.xcodeproj from project.yml
	xcodegen generate --spec project.yml

fetch-llama: ## Download and verify the pinned llama.cpp xcframework
	./scripts/fetch-llama.sh

build-for-testing: generate ## Build the app and both test bundles for the simulator
	@mkdir -p .build/Logs
	@rm -rf .build/Logs/Build.xcresult
	xcodebuild build-for-testing \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(SIMULATOR)' \
		-derivedDataPath $(DERIVED_DATA) \
		-resultBundlePath .build/Logs/Build.xcresult \
		CODE_SIGNING_ALLOWED=NO \
		COMPILER_INDEX_STORE_ENABLE=NO

test: build-for-testing test-unit test-ui ## Build once, then run unit and UI tests

test-unit: ## Run unit tests without rebuilding
	@mkdir -p .build/Logs
	@rm -rf .build/Logs/Unit.xcresult
	@xctestrun=$$(ls -t $(DERIVED_DATA)/Build/Products/*PLaMoTranslate*.xctestrun | head -1); \
	xcodebuild test-without-building \
		-xctestrun "$$xctestrun" \
		-destination '$(SIMULATOR)' \
		-only-testing:KotobaTests \
		-resultBundlePath .build/Logs/Unit.xcresult \
		CODE_SIGNING_ALLOWED=NO

test-ui: ## Run XCUITest E2E tests without rebuilding
	@mkdir -p .build/Logs
	@rm -rf .build/Logs/UI.xcresult
	@xctestrun=$$(ls -t $(DERIVED_DATA)/Build/Products/*PLaMoTranslate*.xctestrun | head -1); \
	xcodebuild test-without-building \
		-xctestrun "$$xctestrun" \
		-destination '$(SIMULATOR)' \
		-only-testing:KotobaUITests \
		-resultBundlePath .build/Logs/UI.xcresult \
		CODE_SIGNING_ALLOWED=NO

build-device: generate fetch-llama ## Unsigned device build (verifies the llama.cpp bridge)
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		COMPILER_INDEX_STORE_ENABLE=NO
	@APP="$(DERIVED_DATA)/Build/Products/Release-iphoneos/Kotoba.app"; \
	test -d "$$APP/Frameworks/llama.framework" || { echo "error: llama.framework was not embedded into $$APP" >&2; exit 1; }; \
	test -d "$$APP/Extensions/PLaMoTranslateExtension.appex" || { echo "error: translation extension was not embedded into $$APP" >&2; exit 1; }; \
	echo "Verified: llama.framework and the Translation UI Provider extension are in Kotoba.app"

clean: ## Remove generated project and build products
	rm -rf $(PROJECT) .build
