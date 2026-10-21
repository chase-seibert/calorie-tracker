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
TEST_DIAGNOSTICS ?= on-failure
SIMULATOR_FIXTURE ?= device
SIMULATOR_FIXTURE_RESET ?= 1
SIMULATOR_GROUP_ID := group.com.cseibert.CalorieTracker

DEVICE_ID ?= 00008150-000E41422E40401C
DEVELOPMENT_TEAM ?= 96NAC4VTEN
PHONE_DESTINATION_TIMEOUT ?= 60
PYTHON ?= python3
OFF_PAGES ?= 10
DEBUG_CATALOG_DIR := data/work/catalogs
DEBUG_REPORT_DIR := data/work/catalog-reports

.PHONY: setup format lint simulator-ready test ui-test-reorder ui-test-fixture build clean catalog catalog-refresh catalog-grouped-report catalog-family-report catalog-debug-off-search-10000 catalog-debug-gap catalog-debug-report catalog-debug sim-compile sim-build sim-runtime-build sim-launch sim-import-fixture phone-build phone-install phone-launch phone-deploy phone-siri-logs phone-diary-performance-logs phone-wifi-check phone-wifi-deploy chase-food-data chase-food-review chase-food-bagel-pdf

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
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerTests test

ui-test-reorder: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testLongPressDragReordersVisuallyAndPersists test

.PHONY: ui-test-duplicate-today
ui-test-duplicate-today: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testStationaryLongPressDuplicatesLoggedFoodToday -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testMultiSelectDuplicatesSelectedFoodsToday test

ui-test-fixture: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testDeviceFixtureShowsRelativeDays test

.PHONY: ui-test-snacks
ui-test-snacks: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testSnackSuggestionsSelectionWithoutRemindersAccess test

.PHONY: ui-test-cheat-day
ui-test-cheat-day: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testCheatDayConfirmationCapsuleAcceptsEdgeTap -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testCheatDayRepeatedConfirmationAndEntryPoints test

build: sim-build

DIARY_TOOL_SOURCES := CalorieTracker/Models/Domain.swift CalorieTracker/Data/FoodResolution.swift CalorieTracker/Data/DiaryEngine.swift CalorieTracker/Data/DiaryRepository.swift CalorieTracker/Data/QuickLogStore.swift CalorieTracker/Data/CatalogStore.swift scripts/DiaryTool.swift

.PHONY: diary-tool storage-test storage-benchmark diary-convert diary-validate search-eval search-analytics icon-review
ICON_DIR ?= docs/icon-concepts/2026-09-02

icon-review:
	mkdir -p build/DiaryModuleCache
	xcrun swift -module-cache-path build/DiaryModuleCache scripts/render_icon_review.swift "$(ICON_DIR)"

diary-tool: build/diary-tool

build/diary-tool: $(DIARY_TOOL_SOURCES)
	mkdir -p build/DiaryModuleCache
	xcrun swiftc -O -swift-version 6 -module-cache-path build/DiaryModuleCache $(DIARY_TOOL_SOURCES) -o $@

storage-test: diary-tool
	build/diary-tool self-test

storage-benchmark: diary-tool
	build/diary-tool benchmark

diary-convert: diary-tool
	@test -n "$(INPUT)" -a -n "$(OUTPUT)" || (echo 'Set INPUT=backup.json OUTPUT=converted.sqlite'; exit 1)
	build/diary-tool convert "$(INPUT)" "$(OUTPUT)"

diary-validate: diary-tool
	@test -n "$(INPUT)" || (echo 'Set INPUT=converted.sqlite'; exit 1)
	build/diary-tool validate "$(INPUT)"

SEARCH_RANKING_VERSION ?= catalog-fts5-v3-canonical-first
SEARCH_EVAL_FIXTURE ?= data/search-eval/relevance-v3.json

search-eval: diary-tool
	CALORIE_SEARCH_RANKING_VERSION="$(SEARCH_RANKING_VERSION)" build/diary-tool search-eval "$(or $(FIXTURE),$(SEARCH_EVAL_FIXTURE))"

SEARCH_ANALYTICS_DB ?= downloads/analytics.sqlite3
SEARCH_ANALYTICS_DAYS ?= 90
SEARCH_ANALYTICS_AUDIENCE ?= production

search-analytics:
	$(PYTHON) scripts/analyze_search_analytics.py --db "$(SEARCH_ANALYTICS_DB)" --days "$(SEARCH_ANALYTICS_DAYS)" --audience "$(SEARCH_ANALYTICS_AUDIENCE)"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) clean

chase-food-data:
	$(PYTHON) scripts/prepare_chase_food_data.py

chase-food-review: chase-food-data
	/Users/cseibert/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node scripts/build_chase_food_review.mjs

chase-food-bagel-pdf:
	swift scripts/render_chase_food_bagel_concept.swift docs/chase-food-bagel-concept.pdf

catalog: chase-food-data
	$(PYTHON) scripts/build_food_catalog.py --output CalorieTracker/Resources/FoodCatalog.sqlite3

.PHONY: catalog-test
catalog-test:
	$(PYTHON) scripts/test_meat_classification.py

catalog-refresh: chase-food-data
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

sim-import-fixture: simulator-ready diary-tool
	@test -n "$(INPUT)" || (echo 'Set INPUT=/private/path/phone-export.sqlite'; exit 1)
	@test -f "$(INPUT)" || (echo "SQLite export not found: $(INPUT)"; exit 1)
	@test ! -e "$(INPUT)-wal" -a ! -e "$(INPUT)-journal" || (echo 'Choose a standalone SQLite export without a WAL or journal sidecar.'; exit 1)
	@set -eu; \
	STAGING_DIR=$$(mktemp -d "$${TMPDIR:-/tmp}/yum-chase-fixture.XXXXXX"); \
	trap 'rm -r "$$STAGING_DIR"' EXIT; \
	cp "$(INPUT)" "$$STAGING_DIR/input.sqlite"; \
	$(MAKE) diary-validate INPUT="$$STAGING_DIR/input.sqlite"; \
	$(MAKE) sim-runtime-build; \
	UDID=$$(xcrun simctl list devices available | awk -F '[()]' -v name="$(SIM_DEVICE_NAME)" '{ display=$$1; sub(/^[[:space:]]+/, "", display); sub(/[[:space:]]+$$/, "", display); if (display == name && $$0 !~ /unavailable/) { print $$2; exit } }'); \
	if [ -z "$$UDID" ]; then \
		echo "No available simulator named $(SIM_DEVICE_NAME)."; \
		xcrun simctl list devices available; \
		exit 1; \
	fi; \
	xcrun simctl boot "$$UDID" >/dev/null 2>&1 || true; \
	xcrun simctl bootstatus "$$UDID" -b; \
	xcrun simctl terminate "$$UDID" $(BUNDLE_ID) >/dev/null 2>&1 || true; \
	xcrun simctl install "$$UDID" "$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(APP_NAME).app"; \
	xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_FIXTURE none; \
	xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE 1; \
	xcrun simctl launch "$$UDID" $(BUNDLE_ID) >/dev/null; \
	GROUP_ROOT=; \
	for _ in $$(seq 1 20); do \
		GROUP_ROOT=$$(xcrun simctl get_app_container "$$UDID" "$(BUNDLE_ID)" groups 2>/dev/null | awk -v group="$(SIMULATOR_GROUP_ID)" '$$1 == group { print $$2; exit }'); \
		[ -n "$$GROUP_ROOT" ] && break; \
		sleep 1; \
	done; \
	xcrun simctl terminate "$$UDID" $(BUNDLE_ID) >/dev/null 2>&1 || true; \
	[ -n "$$GROUP_ROOT" ] || { echo 'The simulator App Group container was not created.'; exit 1; }; \
	FIXTURE_ID=$$(uuidgen | tr '[:upper:]' '[:lower:]'); \
	FIXTURE_DIR="$$GROUP_ROOT/CalorieTracker/Fixtures"; \
	mkdir -p "$$FIXTURE_DIR"; \
	cp "$$STAGING_DIR/input.sqlite" "$$FIXTURE_DIR/$$FIXTURE_ID.sqlite"; \
	xcrun simctl spawn "$$UDID" defaults write "$(SIMULATOR_GROUP_ID)" debug.fixture.device "$$FIXTURE_ID"; \
	xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_FIXTURE device; \
	xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_DISABLE_SIMULATOR_FIXTURE 1; \
	xcrun simctl spawn "$$UDID" launchctl setenv CALORIE_TRACKER_FIXTURE_RESET 0; \
	if [ -d "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" ]; then \
		open -a Simulator --args -CurrentDeviceUDID "$$UDID" || true; \
	fi; \
	xcrun simctl launch "$$UDID" $(BUNDLE_ID); \
	echo "Imported $(INPUT) as simulator fixture $$FIXTURE_ID for $(SIM_DEVICE_NAME)."

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

PHONE_SIRI_LOG_OUTPUT ?= /tmp/YumChase-siri-quick-log.jsonl
PHONE_DIARY_PERFORMANCE_LOG_OUTPUT ?= /tmp/YumChase-diary-performance.jsonl

phone-siri-logs:
	@set -eu; \
		mkdir -p "$$(dirname "$(PHONE_SIRI_LOG_OUTPUT)")"; \
		xcrun devicectl device copy from \
		  --device $(DEVICE_ID) \
		  --domain-type appGroupDataContainer \
		  --domain-identifier $(SIMULATOR_GROUP_ID) \
		  --source Library/Diagnostics/siri-quick-log.jsonl \
		  --destination "$(PHONE_SIRI_LOG_OUTPUT)"; \
		xcrun devicectl device copy from \
		  --device $(DEVICE_ID) \
		  --domain-type appGroupDataContainer \
		  --domain-identifier $(SIMULATOR_GROUP_ID) \
		  --source Library/Diagnostics/siri-quick-log.jsonl.1 \
		  --destination "$(PHONE_SIRI_LOG_OUTPUT).1" >/dev/null 2>&1 || true; \
		echo "Copied Yum Chase Siri diagnostics to $(PHONE_SIRI_LOG_OUTPUT)."

phone-diary-performance-logs:
	@set -eu; \
		mkdir -p "$$(dirname "$(PHONE_DIARY_PERFORMANCE_LOG_OUTPUT)")"; \
		xcrun devicectl device copy from \
		  --device $(DEVICE_ID) \
		  --domain-type appGroupDataContainer \
		  --domain-identifier $(SIMULATOR_GROUP_ID) \
		  --source Library/Diagnostics/diary-performance.jsonl \
		  --destination "$(PHONE_DIARY_PERFORMANCE_LOG_OUTPUT)"; \
		xcrun devicectl device copy from \
		  --device $(DEVICE_ID) \
		  --domain-type appGroupDataContainer \
		  --domain-identifier $(SIMULATOR_GROUP_ID) \
		  --source Library/Diagnostics/diary-performance.jsonl.1 \
		  --destination "$(PHONE_DIARY_PERFORMANCE_LOG_OUTPUT).1" >/dev/null 2>&1 || true; \
		echo "Copied Yum Chase diary performance diagnostics to $(PHONE_DIARY_PERFORMANCE_LOG_OUTPUT)."

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

.PHONY: ui-test-food-detail
ui-test-food-detail: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testMagicGroupedSuggestionItemsOpenCustomization -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testLoggedFoodReturnsToSharedCustomizationAndNestedCancelIsSafe -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testLoggedFoodMeatClassificationChoicesPersistIndependently -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testSharedMealCompositionUsesFoodSearchAndCancelsParentDraft -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testMixedCatalogCustomizationAndScreenshotMatrix -only-testing:CalorieTrackerUITests/DeviceFixtureUITests/testMixedCatalogQuickAddIsIndependentFromDetail test

.PHONY: ui-test-saved-variations
ui-test-saved-variations: simulator-ready
	xcodebuild -project $(PROJECT) -scheme CalorieTrackerUITests -configuration $(CONFIGURATION) -destination '$(SIM_DESTINATION)' -destination-timeout $(SIMULATOR_DESTINATION_TIMEOUT) -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics $(TEST_DIAGNOSTICS) -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testSavedVariationQuickAddCenterCoordinateUsesTheTappedProteinShake -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testSavedVariationQuickAddLowerEdgeUsesTheTappedProteinShake -only-testing:CalorieTrackerUITests/DiaryReorderingUITests/testSavedVariationQuickAddRightSideUsesTheTappedProteinShake test

.PHONY: export-food-detail-evidence
export-food-detail-evidence:
	@test -n "$(RESULT_BUNDLE)" || (echo 'Usage: make export-food-detail-evidence RESULT_BUNDLE=/path/to/test.xcresult'; exit 1)
	python3 scripts/export_food_detail_evidence.py "$(RESULT_BUNDLE)"
