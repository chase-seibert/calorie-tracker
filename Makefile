PROJECT := CalorieTracker.xcodeproj
SCHEME := CalorieTracker
CONFIGURATION := Debug
DERIVED_DATA := build
APP_NAME := CalorieTracker
BUNDLE_ID := com.cseibert.CalorieTracker

SIM_DEVICE_NAME ?= iPhone 17 Pro
SIM_DESTINATION ?= platform=iOS Simulator,name=$(SIM_DEVICE_NAME)
GENERIC_SIM_DESTINATION := generic/platform=iOS Simulator
SIMULATOR_DESTINATION_TIMEOUT ?= 15
SIMULATOR_FIXTURE ?= device
SIMULATOR_FIXTURE_RESET ?= 1

DEVICE_ID ?= 00008150-000E41422E40401C
DEVELOPMENT_TEAM ?= 96NAC4VTEN
PHONE_DESTINATION_TIMEOUT ?= 60
PYTHON ?= python3
OFF_PAGES ?= 10
DEBUG_CATALOG_DIR := data/work/catalogs
DEBUG_REPORT_DIR := data/work/catalog-reports

.PHONY: setup format lint simulator-ready test ui-test-reorder ui-test-fixture build clean catalog catalog-refresh catalog-grouped-report catalog-family-report catalog-debug-off-search-10000 catalog-debug-gap catalog-debug-report catalog-debug sim-compile sim-build sim-runtime-build sim-launch phone-build phone-install phone-launch phone-deploy phone-wifi-check phone-wifi-deploy

setup: catalog

format:
	@echo "Swift source uses Xcode's built-in formatting; no external formatter required."

lint:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -sdk iphonesimulator -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO analyze

simulator-ready:
	@set -eu; \
	if ! xcrun simctl list devices available >/dev/null 2>&1; then \
	  echo "CoreSimulator is unavailable; simulator tests cannot run."; \
	  echo "Restart Simulator or Xcode, then rerun this command."; \
	  exit 1; \
	fi; \
	if ! xcrun simctl list devices available | awk -F '[()]' -v name="$(SIM_DEVICE_NAME)" '{ display=$$1; sub(/^[[:space:]]+/, "", display); sub(/[[:space:]]+$$/, "", display); if (display == name && $$0 !~ /unavailable/) { found=1 } } END { exit !found }'; then \
	  echo "No available simulator named $(SIM_DEVICE_NAME)."; \
	  echo "Create or install it in Xcode, or override SIM_DEVICE_NAME and rerun."; \
	  exit 1; \
	fi

test: simulator-ready
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -only-testing:CalorieTrackerTests test

ui-test-reorder: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testLongPressDragReordersVisuallyAndPersists test

ui-test-fixture: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testDeviceFixtureShowsRelativeDays test

build: sim-build

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) clean

catalog:
	$(PYTHON) scripts/build_food_catalog.py --output CalorieTracker/Resources/FoodCatalog.sqlite3

catalog-refresh:
	$(PYTHON) scripts/build_food_catalog.py --download --off-pages $(OFF_PAGES) --output CalorieTracker/Resources/FoodCatalog.sqlite3

catalog-grouped-report:
	$(PYTHON) scripts/build_grouped_food_catalog.py \
	  --input CalorieTracker/Resources/FoodCatalog.sqlite3 \
	  --output $(DEBUG_CATALOG_DIR)/grouped-food-catalog.sqlite3 \
	  --report $(DEBUG_REPORT_DIR)/grouped-food-catalog.html

catalog-family-report:
	$(PYTHON) scripts/build_food_family_catalog.py \
	  --input CalorieTracker/Resources/FoodCatalog.sqlite3 \
	  --output $(DEBUG_CATALOG_DIR)/food-family-catalog.sqlite3 \
	  --report $(DEBUG_REPORT_DIR)/food-family-catalog.html

catalog-debug-off-search-10000:
	$(PYTHON) scripts/build_food_catalog.py --download --off-search --off-products 10000 --output $(DEBUG_CATALOG_DIR)/catalog-off-search-top-10000.sqlite3

catalog-debug-gap:
	$(PYTHON) scripts/build_gap_catalog.py --output $(DEBUG_CATALOG_DIR)/catalog-gap-search.sqlite3

catalog-debug-report:
	$(PYTHON) scripts/probe_catalog_coverage.py \
	  --catalog bundled=CalorieTracker/Resources/FoodCatalog.sqlite3 \
	  --catalog off-search-top-10000=$(DEBUG_CATALOG_DIR)/catalog-off-search-top-10000.sqlite3 \
	  --catalog gap-search=$(DEBUG_CATALOG_DIR)/catalog-gap-search.sqlite3 \
	  --output $(DEBUG_REPORT_DIR)/missing-foods.md

catalog-debug: catalog-debug-off-search-10000 catalog-debug-gap catalog-debug-report

sim-compile:
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) \
	  -sdk iphonesimulator \
	  -derivedDataPath $(DERIVED_DATA) \
	  CODE_SIGNING_ALLOWED=NO \
	  build

sim-build: sim-compile

sim-runtime-build:
	xcodebuild \
	  -project $(PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration $(CONFIGURATION) \
	  -destination '$(GENERIC_SIM_DESTINATION)' \
	  -derivedDataPath $(DERIVED_DATA) \
	  build

sim-launch: sim-runtime-build
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
	if [ "$(SIMULATOR_FIXTURE)" = "device" ]; then \
		xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_FIXTURE device; \
		xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE 0; \
	else \
		xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_FIXTURE none; \
		xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE 1; \
	fi; \
	xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_FIXTURE_RESET "$(SIMULATOR_FIXTURE_RESET)"; \
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
