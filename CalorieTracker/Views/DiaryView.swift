import SwiftUI
import UIKit

struct DiaryView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    #if DEBUG
        @AppStorage("experimental.alwaysShowQuickCalories") private var alwaysShowQuickCalories = false
    #else
        private let alwaysShowQuickCalories = false
    #endif
    let catalog: CatalogStore
    @Binding var foodPickerLaunch: FoodPickerLaunch?

    @State private var dayOffset = 0
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var showingMealName = false
    @State private var showingDeleteConfirmation = false
    @State private var mealName = ""
    @State private var isSelectingMealItems = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var editingEntry: DiaryEntry?
    @State private var isMacroSummaryVisible = true
    @State private var showingTrends = ProcessInfo.processInfo.arguments.contains("--show-trends")
    @State private var showingStreak = ProcessInfo.processInfo.arguments.contains("--show-streak-report")
    @State private var showingAlcoholEntry = false
    @State private var showingDailyNoteEditor = false
    @State private var dailyNoteDraft = ""
    @State private var diaryEntriesHeight: CGFloat = 0
    @State private var showingBottomCheatPopover = false
    @State private var showingBannerCheatPopover = false
    @State private var showingLogFoodCheatPopover = false
    @State private var didSeedDebugScreenshot = false
    @State private var activeCheatDayDiagnosticsID: String?
    @State private var activeCheatDayStartedAt: UInt64?

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: currentDay) ?? currentDay
    }

    private var selectedDayStatus: DayStatus? { diary.status(on: date) }
    private var isCheatDay: Bool { selectedDayStatus?.kind == .cheat }
    private var isFutureDay: Bool { date > Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        DateStrip(dayOffset: $dayOffset, referenceDay: currentDay)
                            .id("date-strip")
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 7)
                        if let status = selectedDayStatus {
                            if status.kind == .cheat {
                                Button {
                                    showingBannerCheatPopover = true
                                } label: {
                                    DayStatusBanner(status: status)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Undo this cheat day")
                                .accessibilityIdentifier("cheat-day-banner")
                                .cheatDayPopover(
                                    isPresented: $showingBannerCheatPopover,
                                    date: date,
                                    isCheatDay: isCheatDay,
                                    arrowEdge: .top,
                                    onConfirm: { diagnosticsID in
                                        confirmCheatDayAction(diagnosticsID: diagnosticsID)
                                    }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                            } else {
                                DayStatusBanner(status: status)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                            }
                        }
                        Button {
                            showingTrends = true
                        } label: {
                            MacroSummary(
                                nutrients: diary.totals(on: date),
                                calorieGoal: diary.dailyCalorieGoal
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows calorie and macro trends over time")
                        .id("macro-summary")
                        .onGeometryChange(for: Bool.self) { geometry in
                            geometry.frame(in: .global).maxY > 120
                        } action: { isVisible in
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isMacroSummaryVisible = isVisible
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 7)
                        .padding(.bottom, 9)
                        entrySection
                    }
                }
                .background(AppTheme.background.ignoresSafeArea())
                .contentMargins(.bottom, 20, for: .scrollContent)
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("--show-scrolled-diary") else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    scrollProxy.scrollTo("logged-heading", anchor: .top)
                }
            }
            .navigationDestination(isPresented: $showingTrends) {
                TrendsView()
            }
            .navigationDestination(isPresented: $showingStreak) {
                StreakReportView()
            }
            .navigationTitle("Yum Chase")
            .toolbar {
                if !isMacroSummaryVisible {
                    ToolbarItem(placement: .principal) {
                        let calorieProgress = DailyCalorieProgress(
                            calories: diary.totals(on: date).calories,
                            goal: diary.dailyCalorieGoal
                        )
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(AppTheme.coral)
                            Text(calorieProgress.consumed.formatted())
                                .font(.headline.monospacedDigit())
                            if let goal = calorieProgress.goal {
                                Text("/ \(goal.formatted())")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(AppTheme.muted)
                            }
                            Text("cal")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(calorieProgress.accessibilityLabel)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                if !isSelectingMealItems {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showingStreak = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                Text(diary.isCalculatingStreak ? "…" : diary.currentStreak.dayCount.formatted())
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(diary.isCalculatingStreak
                                ? "Calculating day streak"
                                : "\(diary.currentStreak.dayCount) day streak")
                        }

                        NavigationLink {
                            SettingsView(catalog: catalog)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectingMealItems {
                    VStack(spacing: 10) {
                        HStack {
                            Text("\(selectedEntryIDs.count) selected")
                                .font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("diary-selection-count")
                            Spacer()
                            Button("Cancel", action: cancelMealSelection)
                                .font(.subheadline.weight(.semibold))
                        }

                        HStack(spacing: 12) {
                            Button {
                                duplicateSelectedEntriesToday()
                            } label: {
                                Text("Log Today")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(selectedEntryIDs.isEmpty)
                            .accessibilityHint("Log selected items today")

                            Button {
                                mealName = ""
                                showingMealName = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title3.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                            .frame(width: 56, height: 56)
                            .tint(AppTheme.coral)
                            .disabled(selectedEntryIDs.isEmpty)
                            .accessibilityLabel("Create Meal")
                            .accessibilityHint("Create a meal from selected items")

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title3.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                            .frame(width: 56, height: 56)
                            .tint(AppTheme.coral)
                            .disabled(selectedEntryIDs.isEmpty)
                            .accessibilityLabel("Delete")
                            .accessibilityHint("Delete selected items")
                            .confirmationDialog(
                                "Delete \(selectedEntryIDs.count) selected item\(selectedEntryIDs.count == 1 ? "" : "s")?",
                                isPresented: $showingDeleteConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    deleteSelectedEntries()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This cannot be undone.")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .controlSize(.large)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            showingBottomCheatPopover = true
                        } label: {
                            CheatDayToolbarIcon(isCheatDay: isCheatDay)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .tint(AppTheme.coral)
                        .disabled(isFutureDay)
                        .accessibilityLabel(isCheatDay ? "Undo cheat day" : "Mark cheat day")
                        .accessibilityIdentifier("cheat-day-toolbar")
                        .cheatDayPopover(
                            isPresented: $showingBottomCheatPopover,
                            date: date,
                            isCheatDay: isCheatDay,
                            arrowEdge: .bottom,
                            onConfirm: { diagnosticsID in
                                confirmCheatDayAction(diagnosticsID: diagnosticsID)
                            }
                        )

                        if tracksAlcohol {
                            Button {
                                beginLoggingAlcohol()
                            } label: {
                                AlcoholActionIcon(drinks: diary.alcoholDrinkCount(on: date))
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                            .tint(AppTheme.coral)
                            .opacity(isCheatDay ? 0.5 : 1)
                            .accessibilityLabel("Log alcohol")
                            .accessibilityValue(alcoholAccessibilityValue)
                        }

                        Button {
                            beginLoggingFood()
                        } label: {
                            Label("Log food", systemImage: "magnifyingglass")
                                .font(.headline)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Capsule())
                        .opacity(isCheatDay ? 0.5 : 1)
                        .cheatDayPopover(
                            isPresented: $showingLogFoodCheatPopover,
                            date: date,
                            isCheatDay: isCheatDay,
                            arrowEdge: .bottom,
                            onConfirm: { diagnosticsID in
                                confirmCheatDayAction(diagnosticsID: diagnosticsID)
                            }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 0)
                    .background(.ultraThinMaterial.opacity(0.78))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("diary-log-food-actions")
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .sheet(item: $foodPickerLaunch) { launch in
                FoodPickerView(date: date, catalog: catalog, initialMode: launch.initialMode)
                    .environmentObject(diary)
            }
            .sheet(isPresented: $showingAlcoholEntry) {
                AlcoholQuickEntryView(date: date, entry: diary.alcoholEntry(on: date))
                    .environmentObject(diary)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingDailyNoteEditor) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $dailyNoteDraft)
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("Day note")
                            .accessibilityIdentifier("daily-note-editor")
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(AppTheme.background.ignoresSafeArea())
                    .navigationTitle("Day Note")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingDailyNoteEditor = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveDailyNote() }
                                .fontWeight(.semibold)
                        }
                        if diary.dailyNote(on: date) != nil {
                            ToolbarItem(placement: .bottomBar) {
                                Button("Clear Note", role: .destructive) { clearDailyNote() }
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $editingEntry) { entry in
                LoggedItemDetailView(entryID: entry.id, catalog: catalog)
                    .environmentObject(diary)
            }
            .alert("Save selected foods as a meal", isPresented: $showingMealName) {
                TextField("Meal name", text: $mealName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveSelectedAsMeal() }
                    .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("The \(selectedEntryIDs.count) selected item\(selectedEntryIDs.count == 1 ? "" : "s") will be replaced by one meal entry.")
            }
            .onChange(of: dayOffset) { _, _ in
                diaryEntriesHeight = CGFloat(diary.entries(on: date).count) * 78
                cancelMealSelection()
            }
            .task(id: date) {
                guard !diary.isLoading else { return }
                await diary.selectDay(date)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshCurrentDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                refreshCurrentDay()
            }
            .task {
                diary.run {
                    #if DEBUG
                        guard !didSeedDebugScreenshot else { return }
                        didSeedDebugScreenshot = true
                        let arguments = ProcessInfo.processInfo.arguments
                        if arguments.contains("--seed-special-days") {
                            try await diary.seedSpecialDaysForScreenshots()
                        }
                        if arguments.contains("--seed-today-cheat") {
                            try await diary.markCheatDay(on: Date(), adjustmentCalories: 1_000)
                        }
                        if arguments.contains("--show-cheat-day-dialog")
                            || arguments.contains("--show-banner-cheat-popover")
                            || arguments.contains("--show-log-food-cheat-popover")
                        {
                            try? await Task.sleep(for: .milliseconds(500))
                            showingBottomCheatPopover = arguments.contains("--show-cheat-day-dialog")
                            showingBannerCheatPopover = arguments.contains("--show-banner-cheat-popover")
                            showingLogFoodCheatPopover = arguments.contains("--show-log-food-cheat-popover")
                        }
                    #endif

                }
            }
        }
        .analyticsScreen("diary")
        .onChange(of: isCheatDay) { _, newValue in
            guard let operationID = activeCheatDayDiagnosticsID else { return }
            var properties = ["is_cheat_day": String(newValue)]
            if let startedAt = activeCheatDayStartedAt {
                properties["ui_elapsed_ms"] = String(
                    format: "%.1f",
                    DiaryPerformanceDiagnostics.elapsedMilliseconds(since: startedAt)
                )
            }
            DiaryPerformanceDiagnostics.record(
                "cheat_day_ui_state_changed",
                operationID: operationID,
                properties: properties
            )
        }
        .onChange(of: diary.isSaving) { _, isSaving in
            guard let operationID = activeCheatDayDiagnosticsID else { return }
            var properties = ["is_saving": String(isSaving)]
            if let startedAt = activeCheatDayStartedAt {
                properties["ui_elapsed_ms"] = String(
                    format: "%.1f",
                    DiaryPerformanceDiagnostics.elapsedMilliseconds(since: startedAt)
                )
            }
            DiaryPerformanceDiagnostics.record(
                "cheat_day_ui_saving_state_changed",
                operationID: operationID,
                properties: properties
            )
        }
    }

    private func refreshCurrentDay() {
        let newCurrentDay = Calendar.current.startOfDay(for: Date())
        guard !Calendar.current.isDate(newCurrentDay, inSameDayAs: currentDay) else { return }
        currentDay = newCurrentDay
    }

    @ViewBuilder
    private var entrySection: some View {
        let entries = diary.entries(on: date)
        let selectableEntries = entries.filter { !$0.isCheatDayAdjustment }
        let alcoholEntry = diary.alcoholEntry(on: date)
        VStack(spacing: 0) {
            HStack {
                Text("Logged")
                    .font(.title3.weight(.bold))
                    .accessibilityIdentifier("logged-heading-label")
                Spacer()
                if !selectableEntries.isEmpty, !isSelectingMealItems, !isCheatDay {
                    Button("Select") {
                        selectedEntryIDs = []
                        isSelectingMealItems = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHint("Choose foods to save as a meal")
                }
            }
            .id("logged-heading")
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 4)
            if isSelectingMealItems, !entries.isEmpty {
                Text("Select items to duplicate, save as a meal, or delete.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 5)
            }
            if !isSelectingMealItems,
                isCheatDay || alwaysShowQuickCalories || diary.calorieAdjustment(on: date) != nil
            {
                CalorieAdjustmentPicker(
                    selectedCalories: diary.calorieAdjustment(on: date),
                    onSelect: { calories in
                        diary.run {
                            do {
                                try await diary.setCalorieAdjustment(calories, on: date)
                            }
                            AppAnalytics.capture(
                                calories == nil
                                    ? "calorie_adjustment.removed"
                                    : "calorie_adjustment.set"
                            )

                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            if entries.isEmpty, alcoholEntry == nil {
                ContentUnavailableView {
                    Label("Nothing logged", systemImage: "leaf")
                } description: {
                    Text("Add a food, or pick one from your recents.")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            } else if isSelectingMealItems {
                ForEach(selectableEntries) { entry in
                    Button {
                        if selectedEntryIDs.contains(entry.id) {
                            selectedEntryIDs.remove(entry.id)
                        } else {
                            selectedEntryIDs.insert(entry.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedEntryIDs.contains(entry.id) ? AppTheme.protein : AppTheme.muted)
                            DiaryEntryRow(entry: entry)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selected-diary-entry-\(entry.food.sourceID)")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            } else {
                VStack(spacing: 0) {
                    if let alcoholEntry {
                        Button {
                            beginLoggingAlcohol()
                        } label: {
                            AlcoholDiaryRow(entry: alcoholEntry)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("logged-alcohol-entry")
                    }

                    if !entries.isEmpty {
                        ReorderableDiaryEntries(
                            entries: entries,
                            contentHeight: $diaryEntriesHeight,
                            onMove: { entryID, destinationIndex in
                                diary.run {
                                    try await diary.moveEntry(entryID, toIndex: destinationIndex, on: date)

                                }
                            },
                            onEdit: { entry in
                                if isCheatDay {
                                    // The list can extend offscreen; anchor confirmation to the fixed toolbar.
                                    showingBottomCheatPopover = true
                                } else if !entry.isCheatDayAdjustment {
                                    editingEntry = entry
                                }
                            },
                            onDuplicateToday: { entry in
                                let today = Calendar.current.startOfDay(for: Date())
                                guard diary.canLogFood(on: today) else {
                                    dayOffset = 0
                                    showingBottomCheatPopover = true
                                    return
                                }
                                diary.run {
                                    try await diary.duplicateEntry(entryID: entry.id, on: today)
                                }
                            },
                            onDelete: { entryID in
                                diary.run {
                                    let itemType =
                                        diary.document.entries.first { $0.id == entryID }?.isMeal == true
                                        ? "meal"
                                        : "food"
                                    do {
                                        try await diary.delete(entryID: entryID)
                                    }
                                    AppAnalytics.capture(
                                        "diary_entry.deleted",
                                        properties: ["item_type": itemType]
                                    )

                                }
                            }
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Logged foods")
                        .accessibilityValue(entries.map(\.food.name).joined(separator: ", "))
                        .accessibilityIdentifier("logged-foods-reorder-list")
                        .frame(height: max(diaryEntriesHeight, CGFloat(entries.count) * 78))
                        .padding(.horizontal, 16)
                    }
                }
            }
            dailyNoteSection
        }
    }

    private var dailyNoteSection: some View {
        DailyNoteSection(note: diary.dailyNote(on: date), onEdit: editDailyNote)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func editDailyNote() {
        dailyNoteDraft = diary.dailyNote(on: date) ?? ""
        showingDailyNoteEditor = true
    }

    private func saveDailyNote() {
        let editedDate = date
        diary.run {
            try await diary.saveDailyNote(dailyNoteDraft, on: editedDate)
            showingDailyNoteEditor = false
        }
    }

    private func clearDailyNote() {
        let editedDate = date
        diary.run {
            try await diary.saveDailyNote(nil, on: editedDate)
            showingDailyNoteEditor = false
        }
    }

    private func saveSelectedAsMeal() {
        diary.run {
            let itemCount = selectedEntryIDs.count
            let previousMealCount = diary.document.meals.count
            try await diary.saveMeal(
                name: mealName,
                replacing: selectedEntryIDs,
                on: date
            )
            if diary.document.meals.count > previousMealCount {
                guard let savedMeal = diary.document.meals.first else { return }
                AppAnalytics.capture(
                    "meal.created",
                    properties: [
                        "origin": "diary_selection",
                        "item_count": String(itemCount),
                    ])
                AppAnalytics.capture(
                    "food_log.completed",
                    properties: FoodLogAnalytics.mealProperties(
                        meal: savedMeal,
                        method: "create_meal",
                        mode: "diary",
                        isFavorite: diary.isFavorite(savedMeal)
                    )
                )
            }
            cancelMealSelection()

        }
    }

    private func cancelMealSelection() {
        isSelectingMealItems = false
        selectedEntryIDs = []
    }

    private func deleteSelectedEntries() {
        diary.run {
            let deletedCount = selectedEntryIDs.count
            do {
                try await diary.deleteEntries(entryIDs: selectedEntryIDs)
            }
            if deletedCount > 0 {
                AppAnalytics.capture(
                    "diary_entry.deleted",
                    properties: [
                        "item_type": "mixed",
                        "item_count": String(deletedCount),
                    ])
            }
            cancelMealSelection()

        }
    }

    private func duplicateSelectedEntriesToday() {
        let today = Calendar.current.startOfDay(for: Date())
        guard diary.canLogFood(on: today) else {
            dayOffset = 0
            showingBottomCheatPopover = true
            return
        }
        let entryIDs = selectedEntryIDs
        diary.run {
            try await diary.duplicateEntries(entryIDs: entryIDs, on: today)
            cancelMealSelection()
        }
    }

    private func beginLoggingFood() {
        guard !isCheatDay else {
            showingLogFoodCheatPopover = true
            return
        }
        foodPickerLaunch = .search
    }

    private func beginLoggingAlcohol() {
        guard !isCheatDay else {
            showingBottomCheatPopover = true
            return
        }
        showingAlcoholEntry = true
    }

    private var alcoholAccessibilityValue: String {
        let drinks = diary.alcoholDrinkCount(on: date)
        return drinks == 1 ? "1 drink" : "\(drinks) drinks"
    }

    private func confirmCheatDayAction(diagnosticsID: String? = nil) {
        // Capture the confirmed intent before a queued action or date navigation changes the view.
        let targetDate = date
        let shouldUndo = isCheatDay
        let preserveAdjustment = alwaysShowQuickCalories
        let dayRelation = analyticsDayRelation
        let operationName = shouldUndo ? "cheat_day_clear" : "cheat_day_mark"
        let operationID = diagnosticsID ?? DiaryPerformanceDiagnostics.newOperationID()
        activeCheatDayDiagnosticsID = operationID
        activeCheatDayStartedAt = DiaryPerformanceDiagnostics.monotonicTimestamp()
        DiaryPerformanceDiagnostics.record(
            "confirmation_received",
            operationID: operationID,
            properties: ["action": shouldUndo ? "clear" : "mark"]
        )
        diary.run(operation: operationName, operationID: operationID) {
            if shouldUndo {
                try await diary.undoCheatDay(
                    on: targetDate,
                    preservingCalorieAdjustment: preserveAdjustment,
                    diagnosticsID: operationID
                )
                AppAnalytics.capture("cheat_day.cleared", properties: ["day": dayRelation])
            } else {
                try await diary.markCheatDay(on: targetDate, diagnosticsID: operationID)
                AppAnalytics.capture("cheat_day.marked", properties: ["day": dayRelation])
            }

        }
    }

    private var analyticsDayRelation: String {
        if Calendar.current.isDateInToday(date) { return "today" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return date < Calendar.current.startOfDay(for: Date()) ? "past" : "future"
    }
}

private struct AlcoholActionIcon: View {
    let drinks: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: drinks > 0 ? "wineglass.fill" : "wineglass")
            if drinks > 0 {
                Text(drinks.formatted())
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
        }
    }
}

private struct AlcoholQuickEntryView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    private let hadExistingEntry: Bool

    @State private var drinks: Int
    @State private var selectedType: AlcoholType?

    init(date: Date, entry: AlcoholEntry?) {
        self.date = date
        hadExistingEntry = entry != nil
        _drinks = State(initialValue: entry?.drinks ?? 1)
        _selectedType = State(initialValue: entry?.type)
    }

    private var caloriesPerDrink: Int {
        selectedType?.caloriesPerDrink ?? AlcoholType.defaultCaloriesPerDrink
    }

    private var estimatedCalories: Int {
        drinks * caloriesPerDrink
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Number of drinks") {
                    HStack(spacing: 24) {
                        Button("Decrease", systemImage: "minus") {
                            drinks = max(drinks - 1, 0)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .disabled(drinks == 0)

                        VStack(spacing: 2) {
                            Text(drinks.formatted())
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .monospacedDigit()
                            Text(drinks == 1 ? "drink" : "drinks")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                        .frame(maxWidth: .infinity)

                        Button("Increase", systemImage: "plus") {
                            drinks += 1
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Picker("Type", selection: $selectedType) {
                        Text("Not specified · \(AlcoholType.defaultCaloriesPerDrink) cal")
                            .tag(nil as AlcoholType?)
                        ForEach(AlcoholType.allCases) { type in
                            Text("\(type.title) · \(type.caloriesPerDrink) cal")
                                .tag(type as AlcoholType?)
                        }
                    }

                    HStack {
                        Text("Estimated calories")
                        Spacer()
                        Text("\(estimatedCalories.formatted()) cal")
                            .foregroundStyle(AppTheme.muted)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Type (optional)")
                } footer: {
                    Text("One calorie estimate applies to all drinks in this quick entry.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Alcohol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        diary.run {
                            try await diary.setAlcohol(
                                drinks: drinks,
                                type: selectedType,
                                on: date,
                                allowCheatDay: true
                            )
                            AppAnalytics.capture(
                                drinks == 0 ? "alcohol.removed" : "alcohol.saved",
                                properties: drinks == 0
                                    ? [:]
                                    : ["operation": hadExistingEntry ? "update" : "create"]
                            )
                            dismiss()

                        }
                    }
                }
            }
            .analyticsScreen(
                "alcohol_editor",
                properties: [
                    "operation": hadExistingEntry ? "edit" : "create"
                ])
        }
    }
}

private struct CheatDayToolbarIcon: View {
    let isCheatDay: Bool

    var body: some View {
        Image(systemName: isCheatDay
              ? "takeoutbag.and.cup.and.straw.fill"
              : "takeoutbag.and.cup.and.straw")
            .font(.body)
    }
}

private struct CheatDayPopoverModifier: ViewModifier {
    @Binding var isPresented: Bool
    let date: Date
    let isCheatDay: Bool
    let arrowEdge: Edge
    let onConfirm: (String) -> Void
    @State private var diagnosticsID: String?

    private var attachmentAnchor: PopoverAttachmentAnchor {
        arrowEdge == .top ? .point(.bottom) : .point(.top)
    }

    func body(content: Content) -> some View {
        content.popover(
            isPresented: $isPresented,
            attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge
        ) {
            CheatDayActionPopover(
                date: date,
                isCheatDay: isCheatDay,
                diagnosticsID: diagnosticsID
            ) { operationID in
                DiaryPerformanceDiagnostics.record(
                    "cheat_day_popover_dismiss_requested",
                    operationID: operationID,
                    properties: ["action": isCheatDay ? "clear" : "mark"]
                )
                isPresented = false
                onConfirm(operationID)
            }
            .onAppear {
                let operationID = DiaryPerformanceDiagnostics.newOperationID()
                diagnosticsID = operationID
                DiaryPerformanceDiagnostics.record(
                    "cheat_day_popover_appeared",
                    operationID: operationID,
                    properties: ["action": isCheatDay ? "clear" : "mark"]
                )
            }
            .onDisappear {
                guard let operationID = diagnosticsID else { return }
                DiaryPerformanceDiagnostics.record(
                    "cheat_day_popover_disappeared",
                    operationID: operationID,
                    properties: ["action": isCheatDay ? "clear" : "mark"]
                )
                diagnosticsID = nil
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

extension View {
    fileprivate func cheatDayPopover(
        isPresented: Binding<Bool>,
        date: Date,
        isCheatDay: Bool,
        arrowEdge: Edge,
        onConfirm: @escaping (String) -> Void
    ) -> some View {
        modifier(CheatDayPopoverModifier(
            isPresented: isPresented,
            date: date,
            isCheatDay: isCheatDay,
            arrowEdge: arrowEdge,
            onConfirm: onConfirm
        ))
    }
}

private struct CheatDayActionPopover: View {
    let date: Date
    let isCheatDay: Bool
    let diagnosticsID: String?
    let onConfirm: (String) -> Void
    @State private var hasConfirmed = false

    private var relativeDayName: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var formattedDate: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isCheatDay ? "Undo \(relativeDayName) Cheat Day?" : "Mark \(relativeDayName) as a Cheat Day?")
                .font(.headline)
            Text(isCheatDay
                 ? "\(formattedDate) will return to normal logging. Any cheat day adjustment will be removed."
                 : "Any food already logged for \(formattedDate) will be kept.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard !hasConfirmed else { return }
                hasConfirmed = true
                let operationID = diagnosticsID ?? DiaryPerformanceDiagnostics.newOperationID()
                DiaryPerformanceDiagnostics.record(
                    "confirmation_button_invoked",
                    operationID: operationID,
                    properties: ["action": isCheatDay ? "clear" : "mark"]
                )
                onConfirm(operationID)
            } label: {
                Text(isCheatDay ? "Undo Cheat Day" : "Yes")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(AppTheme.coral, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(hasConfirmed)
            .accessibilityIdentifier("cheat-day-confirm")
        }
        .padding(18)
        .frame(width: 310)
    }
}

private struct CalorieAdjustmentPicker: View {
    let selectedCalories: Int?
    let onSelect: (Int?) -> Void

    private let options = [500, 1_000, 1_500, 2_000]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Add estimated calories")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if selectedCalories != nil {
                    Button("Remove", role: .destructive) {
                        onSelect(nil)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(options, id: \.self) { calories in
                    let isSelected = selectedCalories == calories
                    Button {
                        onSelect(calories)
                    } label: {
                        HStack(spacing: 3) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.black))
                            }
                            Text("+\(calories.formatted())")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(isSelected ? .white : AppTheme.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? AppTheme.coral : AppTheme.coral.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Estimate \(calories) additional calories")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Text("Available on any day; choosing another amount replaces the current estimate.")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(13)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

enum FoodPickerLaunch: Identifiable {
    case search
    case mode(FoodPickerView.Mode)

    var id: String {
        switch self {
        case .search:
            "search"
        case .mode(let mode):
            "mode-\(mode.rawValue)"
        }
    }

    var initialMode: FoodPickerView.Mode? {
        switch self {
        case .search:
            nil
        case .mode(let mode):
            mode
        }
    }

    static var initialLaunch: FoodPickerLaunch? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-magic-food-picker") {
            return .mode(.magic)
        }
        guard arguments.contains("--show-food-search") || arguments.contains("--show-food-picker") else {
            return nil
        }
        return .search
    }
}

private struct DateStrip: View {
    @Binding var dayOffset: Int
    let referenceDay: Date

    var body: some View {
        HStack(spacing: 8) {
            dayButton(offset: -1, title: "Yesterday")
            dayButton(offset: 0, title: "Today")
            dayButton(offset: 1, title: "Tomorrow")
        }
        .padding(5)
        .background(AppTheme.controlFill, in: Capsule())
        .animation(.snappy, value: dayOffset)
    }

    private func dayButton(offset: Int, title: String) -> some View {
        Button {
            dayOffset = offset
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(date(offset).formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(dayOffset == offset ? AppTheme.selectedText : AppTheme.ink)
            .background(dayOffset == offset ? AppTheme.ink : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func date(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: referenceDay) ?? referenceDay
    }
}

private struct DayStatusBanner: View {
    let status: DayStatus

    private var color: Color {
        status.kind == .gap ? AppTheme.gapDay : AppTheme.cheatDay
    }

    var body: some View {
        HStack(spacing: 10) {
            if status.kind == .gap {
                Image(systemName: "pause.circle.fill")
                    .font(.title3)
                    .padding(.horizontal, 4)
            } else {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .font(.title3)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(status.kind.title)
                    .font(.subheadline.weight(.bold))
                if status.kind == .gap {
                    Text("Nothing was logged after the day ended.")
                } else if let adjustment = status.adjustmentCalories {
                    Text("Includes a \(adjustment.formatted()) calorie estimate.")
                } else {
                    Text("Food is preserved; Apple Health receives zero nutrition.")
                }
            }
            .font(.caption)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(14)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct CalorieProgressIcon: View {
    let progress: Double?
    let consumed: Int
    let goal: Int?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(AppTheme.coral.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.coral)

                Circle()
                    .stroke(AppTheme.coral.opacity(0.2), lineWidth: 3)

                if let progress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AppTheme.coral,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 60, height: 60)

            if let goal {
                Text("\(consumed.formatted()) / \(goal.formatted())")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize()
            }
        }
        .frame(minWidth: 60)
        .animation(.easeInOut(duration: 0.25), value: progress)
        .accessibilityHidden(true)
    }
}

private struct MacroSummary: View {
    let nutrients: MacroNutrients
    let calorieGoal: Int?

    var body: some View {
        let calorieProgress = DailyCalorieProgress(
            calories: nutrients.calories,
            goal: calorieGoal
        )
        let carbs = max(nutrients.carbs, 0)
        let fat = max(nutrients.fat, 0)
        let protein = max(nutrients.protein, 0)
        let macroTotal = carbs + fat + protein
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    if let over = calorieProgress.over, over > 0 {
                        Text(over.formatted())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.coral)
                        Text("calories over")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    } else if let remaining = calorieProgress.remaining {
                        Text(remaining.formatted())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("calories left")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    } else {
                        Text(calorieProgress.consumed.formatted())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("calories")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(calorieProgress.accessibilityLabel)
                Spacer()
                CalorieProgressIcon(
                    progress: calorieProgress.fraction,
                    consumed: calorieProgress.consumed,
                    goal: calorieProgress.goal
                )
            }
            VStack(spacing: 10) {
                stackedMacroBar(carbs: carbs, fat: fat, protein: protein, total: macroTotal)
                HStack(spacing: 8) {
                    macroLegend("Carbs", value: nutrients.carbs, color: AppTheme.carbs)
                    macroLegend("Fat", value: nutrients.fat, color: AppTheme.fat)
                    macroLegend("Protein", value: nutrients.protein, color: AppTheme.protein)
                }
            }
        }
        .padding(20)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }

    private func stackedMacroBar(
        carbs: Double,
        fat: Double,
        protein: Double,
        total: Double
    ) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.controlFill)
                if total > 0 {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(AppTheme.carbs)
                            .frame(width: geometry.size.width * CGFloat(carbs / total))
                        Rectangle()
                            .fill(AppTheme.fat)
                            .frame(width: geometry.size.width * CGFloat(fat / total))
                        Rectangle()
                            .fill(AppTheme.protein)
                            .frame(width: geometry.size.width * CGFloat(protein / total))
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Carbs, \(carbs.cleanAmount) grams; fat, \(fat.cleanAmount) grams; protein, \(protein.cleanAmount) grams"
        )
    }

    private func macroLegend(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Text("\(value.cleanAmount)g")
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.cleanAmount) grams")
    }
}

private struct DiaryEntryRow: View {
    let entry: DiaryEntry

    var body: some View {
        HStack(spacing: 12) {
            if entry.isCheatDayAdjustment {
                Image(systemName: "plusminus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.cheatDay)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.cheatDay.opacity(0.12), in: Circle())
                    .accessibilityLabel("Calorie adjustment")
            } else if !entry.isMeal {
                SourceBadge(source: entry.food.source)
            } else {
                MealBadge()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.food.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(quantityDescription)
                    if let brand = entry.food.displayBrand { Text("· \(brand)") }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
                if let components = entry.foodConfigurationSnapshot?.components, !components.isEmpty {
                    Text(components.map { $0.food.name }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                        .accessibilityLabel("Contains \(components.map { $0.food.name }.joined(separator: ", "))")
                }
            }
            Spacer()
            Text("\(Int(entry.nutrients.calories.rounded()))")
                .font(.headline.monospacedDigit())
            Text("cal")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var quantityDescription: String {
        switch entry.unit {
        case .grams, .ounces:
            "\(entry.amount.cleanAmount) \(entry.unit.rawValue)"
        case .serving:
            "\(entry.amount.cleanAmount) \(entry.food.portion(id: entry.portionID)?.label ?? "serving")"
        }
    }
}

private struct AlcoholDiaryRow: View {
    let entry: AlcoholEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wineglass.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.coral)
                .frame(width: 38, height: 38)
                .background(AppTheme.coral.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.type?.title ?? "Alcohol")
                    .font(.body.weight(.semibold))
                Text(drinkDescription)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            Text(entry.calories.formatted())
                .font(.headline.monospacedDigit())
            Text("cal")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(entry.type?.title ?? "Alcohol"), \(drinkDescription), \(entry.calories) calories"
        )
        .accessibilityHint("Edits this alcohol entry")
    }

    private var drinkDescription: String {
        let count = entry.drinks == 1 ? "1 drink" : "\(entry.drinks) drinks"
        return entry.type == nil ? "\(count) · default estimate" : count
    }
}

private struct ReorderableDiaryEntries: UIViewRepresentable {
    let entries: [DiaryEntry]
    @Binding var contentHeight: CGFloat
    let onMove: (UUID, Int) -> Void
    let onEdit: (DiaryEntry) -> Void
    let onDuplicateToday: (DiaryEntry) -> Void
    let onDelete: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> IntrinsicCollectionView {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = false
        configuration.trailingSwipeActionsConfigurationProvider = { [weak coordinator = context.coordinator] indexPath in
            coordinator?.swipeActions(at: indexPath)
        }

        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        let collectionView = IntrinsicCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.automaticallyAdjustsScrollIndicatorInsets = false
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
        collectionView.scrollsToTop = false
        collectionView.alwaysBounceVertical = false
        collectionView.clipsToBounds = true
        collectionView.dataSource = context.coordinator
        collectionView.register(
            UICollectionViewCell.self,
            forCellWithReuseIdentifier: Coordinator.reuseIdentifier
        )

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        longPress.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(longPress)
        context.coordinator.collectionView = collectionView
        collectionView.reloadData()
        reportContentHeight(from: collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: IntrinsicCollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(entries: entries, to: collectionView)
        reportContentHeight(from: collectionView)
    }

    private func reportContentHeight(from collectionView: IntrinsicCollectionView) {
        let heightBinding = $contentHeight
        collectionView.onContentHeightChange = { height in
            guard height > 0, abs(heightBinding.wrappedValue - height) > 0.5 else { return }
            DispatchQueue.main.async {
                heightBinding.wrappedValue = height
            }
        }
        collectionView.layoutIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource {
        static let reuseIdentifier = "DiaryEntryCell"

        var parent: ReorderableDiaryEntries
        var currentEntries: [DiaryEntry]
        weak var collectionView: UICollectionView?
        private var longPressIndexPath: IndexPath?
        private var longPressOrigin: CGPoint?
        private var editMenuDelegates: [ObjectIdentifier: DiaryEntryEditMenuDelegate] = [:]
        private(set) var isReordering = false

        init(parent: ReorderableDiaryEntries) {
            self.parent = parent
            currentEntries = parent.entries
        }

        func apply(entries: [DiaryEntry], to collectionView: UICollectionView) {
            guard currentEntries != entries else { return }
            guard !isReordering else { return }
            currentEntries = entries
            collectionView.reloadData()
            collectionView.invalidateIntrinsicContentSize()
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            currentEntries.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.reuseIdentifier,
                for: indexPath
            )
            guard currentEntries.indices.contains(indexPath.item) else { return cell }
            let entry = currentEntries[indexPath.item]
            cell.accessibilityIdentifier = "diary-entry-\(entry.food.sourceID)"
            cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
            if !cell.interactions.contains(where: { $0 is UIEditMenuInteraction }) {
                let menuDelegate = DiaryEntryEditMenuDelegate()
                editMenuDelegates[ObjectIdentifier(cell)] = menuDelegate
                cell.addInteraction(UIEditMenuInteraction(delegate: menuDelegate))
            }
            if let menuDelegate = editMenuDelegates[ObjectIdentifier(cell)] {
                menuDelegate.entry = entry
                menuDelegate.onDuplicateToday = parent.onDuplicateToday
            }
            cell.contentConfiguration = UIHostingConfiguration { [weak self] in
                DiaryEntryRow(entry: entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    self?.parent.onEdit(entry)
                }
                .accessibilityAction(named: "Edit quantity") {
                    self?.parent.onEdit(entry)
                }
                .accessibilityAction(named: "Duplicate Today") {
                    self?.parent.onDuplicateToday(entry)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("diary-entry-\(entry.food.sourceID)")
                .padding(.vertical, 6)
            }
            .margins(.all, 0)
            .minSize(height: 78)
            .background(Color.clear)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            guard currentEntries.indices.contains(indexPath.item) else { return false }
            return !currentEntries[indexPath.item].isCheatDayAdjustment
        }

        func collectionView(
            _ collectionView: UICollectionView,
            moveItemAt sourceIndexPath: IndexPath,
            to destinationIndexPath: IndexPath
        ) {
            guard
                currentEntries.indices.contains(sourceIndexPath.item),
                destinationIndexPath.item >= 0,
                destinationIndexPath.item < currentEntries.count
            else { return }

            let movedEntry = currentEntries.remove(at: sourceIndexPath.item)
            currentEntries.insert(movedEntry, at: destinationIndexPath.item)
            parent.onMove(movedEntry.id, destinationIndexPath.item)
        }

        func swipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard currentEntries.indices.contains(indexPath.item) else { return nil }
            guard !currentEntries[indexPath.item].isCheatDayAdjustment else { return nil }
            let entryID = currentEntries[indexPath.item].id
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.parent.onDelete(entryID)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            let configuration = UISwipeActionsConfiguration(actions: [delete])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let collectionView else { return }
            let location = gesture.location(in: collectionView)

            switch gesture.state {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(at: location) else { return }
                guard currentEntries.indices.contains(indexPath.item), !currentEntries[indexPath.item].isCheatDayAdjustment else { return }
                longPressIndexPath = indexPath
                longPressOrigin = location
            case .changed:
                if isReordering {
                    collectionView.updateInteractiveMovementTargetPosition(location)
                    return
                }
                guard
                    let indexPath = longPressIndexPath,
                    let origin = longPressOrigin,
                    hypot(location.x - origin.x, location.y - origin.y) >= 12
                else { return }
                isReordering = collectionView.beginInteractiveMovementForItem(at: indexPath)
                if isReordering { collectionView.updateInteractiveMovementTargetPosition(location) }
            case .ended:
                if isReordering {
                    collectionView.endInteractiveMovement()
                    isReordering = false
                } else if
                    let indexPath = longPressIndexPath,
                    currentEntries.indices.contains(indexPath.item),
                    let cell = collectionView.cellForItem(at: indexPath),
                    let interaction = cell.interactions.compactMap({ $0 as? UIEditMenuInteraction }).first,
                    !currentEntries[indexPath.item].isCheatDayAdjustment
                {
                    let entry = currentEntries[indexPath.item]
                    let menuDelegate = editMenuDelegates[ObjectIdentifier(cell)]
                    menuDelegate?.entry = entry
                    menuDelegate?.onDuplicateToday = parent.onDuplicateToday
                    let sourcePoint = gesture.location(in: interaction.view)
                    interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: sourcePoint))
                }
                longPressIndexPath = nil
                longPressOrigin = nil
            case .cancelled, .failed:
                if isReordering {
                    collectionView.cancelInteractiveMovement()
                    isReordering = false
                }
                longPressIndexPath = nil
                longPressOrigin = nil
            default:
                break
            }
        }
    }
}

@MainActor
private final class DiaryEntryEditMenuDelegate: NSObject, @preconcurrency UIEditMenuInteractionDelegate {
    var entry: DiaryEntry?
    var onDuplicateToday: ((DiaryEntry) -> Void)?

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard entry != nil else { return nil }
        let duplicate = UIAction(title: "Duplicate Today", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
            guard let self, let entry = self.entry else { return }
            self.onDuplicateToday?(entry)
        }
        return UIMenu(children: [duplicate])
    }
}

private final class IntrinsicCollectionView: UICollectionView {
    var onContentHeightChange: ((CGFloat) -> Void)?

    override var contentSize: CGSize {
        didSet {
            guard oldValue != contentSize else { return }
            invalidateIntrinsicContentSize()
            onContentHeightChange?(contentSize.height)
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentSize.height)
    }
}

private struct DailyNoteSection: View {
    let note: String?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("daily-note-text")
            }
            Button(note == nil ? "Add Note" : "Edit", action: onEdit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .accessibilityIdentifier(note == nil ? "add-daily-note" : "edit-daily-note")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SourceBadge: View {
    let source: FoodSource

    var body: some View {
        Text(source.shortTitle)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.12), in: Circle())
            .accessibilityLabel(source.title)
    }

    private var color: Color {
        switch source {
        case .usda: AppTheme.protein
        case .openFoodFacts: AppTheme.carbs
        case .chaseFood, .custom: AppTheme.coral
        }
    }
}

struct MealBadge: View {
    var body: some View {
        Text("Meal")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.coral)
            .frame(width: 38, height: 38)
            .background(AppTheme.coral.opacity(0.12), in: Circle())
            .accessibilityLabel("Saved meal")
    }
}
