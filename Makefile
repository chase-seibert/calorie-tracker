PROJECT := CalorieTracker.xcodeproj
SCHEME := CalorieTracker
CONFIGURATION := Debug
DERIVED_DATA := build
APP_NAME := CalorieTracker
BUNDLE_ID := com.cseibert.CalorieTracker

SIM_DEVICE_NAME ?= iPhone 17 Pro
SIM_DESTINATION ?= platform=iOS Simulator,name=$(SIM_DEVICE_NAME)
GENERIC_SIM_DESTINATION := generic/platform=iOS Simulator

DEVICE_ID ?= 00008150-000E41422E40401C
DEVELOPMENT_TEAM ?= 96NAC4VTEN
PHONE_DESTINATION_TIMEOUT ?= 60
PYTHON ?= python3
OFF_PAGES ?= 10

.PHONY: setup format lint test ui-test-reorder build clean catalog catalog-refresh sim-build sim-launch phone-build phone-install phone-launch phone-deploy phone-wifi-check phone-wifi-deploy

setup: catalog

format:
	@echo "Swift source uses Xcode's built-in formatting; no external formatter required."

lint:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(GENERIC_SIM_DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO analyze

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -only-testing:CalorieTrackerTests test

ui-test-reorder:
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testLongPressDragReordersVisuallyAndPersists test

build: sim-build

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) clean

catalog:
	$(PYTHON) scripts/build_food_catalog.py --output CalorieTracker/Resources/FoodCatalog.sqlite3

catalog-refresh:
	$(PYTHON) scripts/build_food_catalog.py --download --off-pages $(OFF_PAGES) --output CalorieTracker/Resources/FoodCatalog.sqlite3

sim-build:
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) \
	  -destination '$(GENERIC_SIM_DESTINATION)' \
	  -derivedDataPath $(DERIVED_DATA) \
	  CODE_SIGNING_ALLOWED=NO \
	  build

sim-launch: sim-build
	@set -eu; \
	UDID=$$(xcrun simctl list devices available | awk -F '[()]' -v name="$(SIM_DEVICE_NAME)" '{ display=$$1; sub(/^[[:space:]]+/, "", display); sub(/[[:space:]]+$$/, "", display); if (display == name && $$0 !~ /unavailable/) { print $$2; exit } }'); \
	if [ -z "$$UDID" ]; then \
	  echo "No available simulator named $(SIM_DEVICE_NAME)."; \
	  xcrun simctl list devices available; \
	  exit 1; \
	fi; \
	xcrun simctl boot "$$UDID" >/dev/null 2>&1 || true; \
	xcrun simctl bootstatus "$$UDID" -b; \
	open -a Simulator --args -CurrentDeviceUDID "$$UDID"; \
	xcrun simctl install "$$UDID" "$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(APP_NAME).app"; \
	xcrun simctl launch "$$UDID" $(BUNDLE_ID)

phone-build:
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) \
	  -destination 'platform=iOS,id=$(DEVICE_ID)' \
	  -destination-timeout $(PHONE_DESTINATION_TIMEOUT) \
	  -derivedDataPath $(DERIVED_DATA) \
	  CODE_SIGN_STYLE=Automatic \
	  DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
	  -allowProvisioningUpdates \
	  -allowProvisioningDeviceRegistration \
	  build

phone-install:
	xcrun devicectl device install app --device $(DEVICE_ID) "$(DERIVED_DATA)/Build/Products/Debug-iphoneos/$(APP_NAME).app"

phone-launch:
	xcrun devicectl device process launch --device $(DEVICE_ID) --terminate-existing $(BUNDLE_ID)

phone-deploy: phone-build phone-install phone-launch

phone-wifi-check:
	@set -eu; \
	if ! xcrun devicectl list devices \
	  --filter "hardwareProperties.udid == '$(DEVICE_ID)' AND State CONTAINS 'available'" \
	  --columns Identifier \
	  --hide-headers \
	  --timeout $(PHONE_DESTINATION_TIMEOUT) | rg -q '[^[:space:]]'; then \
	  echo "No reachable paired iPhone with UDID $(DEVICE_ID)."; \
	  echo "In Xcode, open Manage Devices from the run-destination menu, pair the iPhone, and select it as the build destination."; \
	  echo "Then disconnect the cable, keep the Mac and unlocked iPhone on the same network, and retry: make phone-wifi-deploy"; \
	  exit 1; \
	fi

phone-wifi-deploy: phone-wifi-check
	@echo "Deploying to paired iPhone over Xcode's available device connection..."
	@$(MAKE) phone-deploy
