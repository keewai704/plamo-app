PROJECT := Kotoba.xcodeproj
SCHEME := Kotoba
DERIVED_DATA := .build/DerivedData
# iPhone or iPad
DEVICE ?= iPhone
SIMULATOR = $(shell ./scripts/select-simulator.sh $(DEVICE))
# Ad-hoc signing keeps the Keychain usable in the simulator without a team.
SIMULATOR_SIGNING := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

.PHONY: generate test-core build-for-testing test-ui build-device

generate:
	xcodegen generate --spec project.yml

test-core:
	swift test --package-path KotobaCore

build-for-testing: generate
	xcodebuild build-for-testing \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIMULATOR)' \
		-derivedDataPath $(DERIVED_DATA) \
		COMPILER_INDEX_STORE_ENABLE=NO \
		$(SIMULATOR_SIGNING)

# Needs a running server: PLAMO_URL, PLAMO_API_KEY.
test-ui:
	TEST_RUNNER_PLAMO_URL="$(PLAMO_URL)" TEST_RUNNER_PLAMO_API_KEY="$(PLAMO_API_KEY)" \
	xcodebuild test-without-building \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIMULATOR)' \
		-derivedDataPath $(DERIVED_DATA) \
		-resultBundlePath .build/Logs/UI-$(DEVICE).xcresult

build-device: generate
	xcodebuild build \
		-project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED_DATA) \
		COMPILER_INDEX_STORE_ENABLE=NO \
		CODE_SIGNING_ALLOWED=NO
