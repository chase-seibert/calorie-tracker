import SwiftUI
import UIKit

struct DiaryView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.scenePhase) private var scenePhase
    let catalog: CatalogStore

    @State private var dayOffset = 0
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var foodPickerLaunch: FoodPickerLaunch? = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-magic-food-picker") {
            return .mode(.magic)
        }
        guard arguments.contains("--show-food-search") || arguments.contains("--show-food-picker") else {
            return nil
        }
        return .search
    }()
    @State private var showingMealName = false
    @State private var showingDeleteConfirmation = false
    @State private var mealName = ""
    @State private var isSelectingMealItems = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var editingEntry: DiaryEntry?
    @State private var isMacroSummaryVisible = true
    @State private var showingTrends = ProcessInfo.processInfo.arguments.contains("--show-trends")
    @State private var showingStreak = ProcessInfo.processInfo.arguments.contains("--show-streak-report")
    @State private var diaryEntriesHeight: CGFloat = 0
    @State private var foodPickerMode: FoodPickerView.Mode?
    @State private var showingToolbarCheatPopover = false
    @State private var showingBannerCheatPopover = false
    @State private var showingLogFoodCheatPopover = false
    @State private var showingModeStripCheatPopover = false
    @State private var showingLoggedEntriesCheatPopover = false
    @State private var didSeedDebugScreenshot = false

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
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Undo this cheat day")
                                .cheatDayPopover(
                                    isPresented: $showingBannerCheatPopover,
                                    date: date,
                                    isCheatDay: isCheatDay,
                                    arrowEdge: .top,
                                    onConfirm: confirmCheatDayAction
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
            .navigationTitle("Calorie Tracker")
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
                            showingToolbarCheatPopover = true
                        } label: {
                            CheatDayToolbarIcon(isCheatDay: isCheatDay)
                        }
                        .tint(AppTheme.coral)
                        .disabled(isFutureDay)
                        .accessibilityLabel(isCheatDay ? "Undo cheat day" : "Mark cheat day")

                        Button {
                            showingStreak = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                Text(diary.currentStreak.dayCount.formatted())
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(diary.currentStreak.dayCount) day streak")
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
                    HStack(spacing: 8) {
                        Button {
                            cancelMealSelection()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .frame(width: 44, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Cancel")

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Text("Delete")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(selectedEntryIDs.isEmpty)
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

                        Button {
                            mealName = ""
                            showingMealName = true
                        } label: {
                            Text("Create meal")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedEntryIDs.isEmpty)
                    }
                    .font(.subheadline.weight(.semibold))
                    .controlSize(.regular)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                } else {
                    VStack(spacing: 0) {
                        Button {
                            beginLoggingFood()
                        } label: {
                            Label("Log food", systemImage: "magnifyingglass")
                                .font(.headline)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Capsule())
                        .opacity(isCheatDay ? 0.5 : 1)
                        .cheatDayPopover(
                            isPresented: $showingLogFoodCheatPopover,
                            date: date,
                            isCheatDay: isCheatDay,
                            arrowEdge: .bottom,
                            onConfirm: confirmCheatDayAction
                        )

                        FoodPickerModeStrip(
                            selection: $foodPickerMode,
                            isEnabled: !isCheatDay,
                            showsScan: false,
                            onDisabledTap: { showingModeStripCheatPopover = true }
                        ) { selectedMode in
                            foodPickerLaunch = .mode(selectedMode)
                        }
                        .cheatDayPopover(
                            isPresented: $showingModeStripCheatPopover,
                            date: date,
                            isCheatDay: isCheatDay,
                            arrowEdge: .bottom,
                            onConfirm: confirmCheatDayAction
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
            .sheet(item: $editingEntry) { entry in
                QuantityEditor(entry: entry)
                    .environmentObject(diary)
                    .presentationDetents([.medium, .large])
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
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshCurrentDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                refreshCurrentDay()
            }
            .task {
#if DEBUG
                guard !didSeedDebugScreenshot else { return }
                didSeedDebugScreenshot = true
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--seed-special-days") {
                    diary.seedSpecialDaysForScreenshots()
                }
                if arguments.contains("--seed-today-cheat") {
                    diary.markCheatDay(on: Date(), adjustmentCalories: 1_000)
                }
                if arguments.contains("--show-cheat-day-dialog")
                    || arguments.contains("--show-banner-cheat-popover")
                    || arguments.contains("--show-log-food-cheat-popover") {
                    try? await Task.sleep(for: .milliseconds(500))
                    showingToolbarCheatPopover = arguments.contains("--show-cheat-day-dialog")
                    showingBannerCheatPopover = arguments.contains("--show-banner-cheat-popover")
                    showingLogFoodCheatPopover = arguments.contains("--show-log-food-cheat-popover")
                }
#endif
            }
        }
        .overlay {
            if showingToolbarCheatPopover {
                ToolbarCheatDayOverlay(
                    date: date,
                    isCheatDay: isCheatDay,
                    onConfirm: {
                        confirmCheatDayAction()
                        showingToolbarCheatPopover = false
                    },
                    onDismiss: { showingToolbarCheatPopover = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: showingToolbarCheatPopover)
    }

    private func refreshCurrentDay() {
        let newCurrentDay = Calendar.current.startOfDay(for: Date())
        guard !Calendar.current.isDate(newCurrentDay, inSameDayAs: currentDay) else { return }
        currentDay = newCurrentDay
    }

    @ViewBuilder
    private var entrySection: some View {
        let entries = diary.entries(on: date)
        VStack(spacing: 0) {
            HStack {
                Text("Logged")
                    .font(.title3.weight(.bold))
                    .accessibilityIdentifier("logged-heading-label")
                Spacer()
                if !entries.isEmpty, !isSelectingMealItems, !isCheatDay {
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
                Text("Choose foods to save as a meal or delete.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 5)
            }
            if isCheatDay {
                CheatDayAdjustmentPicker(
                    selectedCalories: selectedDayStatus?.adjustmentCalories,
                    onSelect: { calories in
                        withAnimation(.snappy) {
                            diary.markCheatDay(on: date, adjustmentCalories: calories)
                        }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            if entries.isEmpty {
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
                ForEach(entries) { entry in
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            } else {
                ReorderableDiaryEntries(
                    entries: entries,
                    contentHeight: $diaryEntriesHeight,
                    onMove: { entryID, destinationIndex in
                        diary.moveEntry(entryID, toIndex: destinationIndex, on: date)
                    },
                    onEdit: { entry in
                        if isCheatDay {
                            showingLoggedEntriesCheatPopover = true
                        } else if !entry.isCheatDayAdjustment {
                            editingEntry = entry
                        }
                    },
                    onDelete: { entryID in
                        withAnimation(.snappy) {
                            diary.delete(entryID: entryID)
                        }
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Logged foods")
                .accessibilityValue(entries.map(\.food.name).joined(separator: ", "))
                .accessibilityIdentifier("logged-foods-reorder-list")
                .frame(height: max(diaryEntriesHeight, CGFloat(entries.count) * 78))
                .padding(.horizontal, 16)
                .cheatDayPopover(
                    isPresented: $showingLoggedEntriesCheatPopover,
                    date: date,
                    isCheatDay: isCheatDay,
                    arrowEdge: .top,
                    onConfirm: confirmCheatDayAction
                )
            }
        }
    }

    private func saveSelectedAsMeal() {
        diary.saveMeal(
            name: mealName,
            replacing: selectedEntryIDs,
            on: date
        )
        cancelMealSelection()
    }

    private func cancelMealSelection() {
        isSelectingMealItems = false
        selectedEntryIDs = []
    }

    private func deleteSelectedEntries() {
        withAnimation(.snappy) {
            diary.deleteEntries(entryIDs: selectedEntryIDs)
        }
        cancelMealSelection()
    }

    private func beginLoggingFood() {
        guard !isCheatDay else {
            showingLogFoodCheatPopover = true
            return
        }
        foodPickerMode = nil
        foodPickerLaunch = .search
    }

    private func confirmCheatDayAction() {
        if isCheatDay {
            diary.undoCheatDay(on: date)
        } else {
            diary.markCheatDay(on: date)
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

private struct ToolbarCheatDayOverlay: View {
    let date: Date
    let isCheatDay: Bool
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.06)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: -1) {
                    UpwardCaret()
                        .fill(.regularMaterial)
                        .frame(width: 24, height: 13)
                        .offset(x: 7)
                    CheatDayActionPopover(
                        date: date,
                        isCheatDay: isCheatDay,
                        onConfirm: onConfirm
                    )
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: .black.opacity(0.13), radius: 22, y: 8)
                }
                .padding(.top, max(proxy.safeAreaInsets.top - 12, 0))
                .padding(.trailing, 8)
            }
        }
    }
}

private struct UpwardCaret: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct CheatDayPopoverModifier: ViewModifier {
    @Binding var isPresented: Bool
    let date: Date
    let isCheatDay: Bool
    let arrowEdge: Edge
    let onConfirm: () -> Void

    private var attachmentAnchor: PopoverAttachmentAnchor {
        arrowEdge == .top ? .point(.bottom) : .point(.top)
    }

    func body(content: Content) -> some View {
        content.popover(
            isPresented: $isPresented,
            attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge
        ) {
            CheatDayActionPopover(date: date, isCheatDay: isCheatDay) {
                onConfirm()
                isPresented = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

private extension View {
    func cheatDayPopover(
        isPresented: Binding<Bool>,
        date: Date,
        isCheatDay: Bool,
        arrowEdge: Edge,
        onConfirm: @escaping () -> Void
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
    let onConfirm: () -> Void

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
            Button(isCheatDay ? "Undo Cheat Day" : "Yes", action: onConfirm)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AppTheme.coral, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 310)
    }
}

private struct CheatDayAdjustmentPicker: View {
    let selectedCalories: Int?
    let onSelect: (Int) -> Void

    private let options = [500, 1_000, 1_500, 2_000]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Estimated extra calories")
                .font(.subheadline.weight(.semibold))
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
            Text("Choosing another amount replaces the current estimate.")
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
        case let .mode(mode):
            "mode-\(mode.rawValue)"
        }
    }

    var initialMode: FoodPickerView.Mode? {
        switch self {
        case .search:
            nil
        case let .mode(mode):
            mode
        }
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
                    .accessibilityLabel("Cheat day adjustment")
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

private struct ReorderableDiaryEntries: UIViewRepresentable {
    let entries: [DiaryEntry]
    @Binding var contentHeight: CGFloat
    let onMove: (UUID, Int) -> Void
    let onEdit: (DiaryEntry) -> Void
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

    final class Coordinator: NSObject, UICollectionViewDataSource {
        static let reuseIdentifier = "DiaryEntryCell"

        var parent: ReorderableDiaryEntries
        var currentEntries: [DiaryEntry]
        weak var collectionView: UICollectionView?
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
            cell.contentConfiguration = UIHostingConfiguration { [weak self] in
                DiaryEntryRow(entry: entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    self?.parent.onEdit(entry)
                }
                .accessibilityAction(named: "Edit quantity") {
                    self?.parent.onEdit(entry)
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
                isReordering = collectionView.beginInteractiveMovementForItem(at: indexPath)
            case .changed where isReordering:
                collectionView.updateInteractiveMovementTargetPosition(location)
            case .ended where isReordering:
                collectionView.endInteractiveMovement()
                isReordering = false
            case .cancelled, .failed:
                guard isReordering else { return }
                collectionView.cancelInteractiveMovement()
                isReordering = false
            default:
                break
            }
        }
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
        case .myFitnessPal: AppTheme.fat
        case .custom: AppTheme.coral
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
