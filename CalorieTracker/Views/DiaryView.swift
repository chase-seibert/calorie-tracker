import SwiftUI
import UniformTypeIdentifiers

struct DiaryView: View {
    @EnvironmentObject private var diary: DiaryStore
    let catalog: CatalogStore

    @State private var dayOffset = 0
    @State private var showingFoodPicker = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--show-food-search") || arguments.contains("--show-food-picker")
    }()
    @State private var showingMealName = false
    @State private var mealName = ""
    @State private var isSelectingMealItems = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var editingEntry: DiaryEntry?
    @State private var draggedEntryID: UUID?
    @State private var isMacroSummaryVisible = true

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        DateStrip(dayOffset: $dayOffset)
                        MacroSummary(
                            nutrients: diary.totals(on: date),
                            calorieGoal: diary.dailyCalorieGoal
                        )
                            .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    isMacroSummaryVisible = isVisible
                                }
                            }
                        entrySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
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
                if isSelectingMealItems {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelMealSelection() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Next (\(selectedEntryIDs.count))") {
                            mealName = ""
                            showingMealName = true
                        }
                        .disabled(selectedEntryIDs.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView(catalog: catalog)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectingMealItems {
                    Text("\(selectedEntryIDs.count) selected")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial)
                } else {
                    Button {
                        showingFoodPicker = true
                    } label: {
                        Label("Log food", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showingFoodPicker) {
                FoodPickerView(date: date, catalog: catalog)
                    .environmentObject(diary)
            }
            .sheet(item: $editingEntry) { entry in
                QuantityEditor(entry: entry)
                    .environmentObject(diary)
                    .presentationDetents([.medium])
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
                draggedEntryID = nil
                cancelMealSelection()
            }
        }
    }

    @ViewBuilder
    private var entrySection: some View {
        let entries = diary.entries(on: date)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Logged")
                    .font(.title3.weight(.bold))
                Spacer()
                if !entries.isEmpty, !isSelectingMealItems {
                    Button("Select") {
                        selectedEntryIDs = []
                        isSelectingMealItems = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHint("Choose foods to save as a meal")
                }
            }
            if isSelectingMealItems, !entries.isEmpty {
                Text("Choose one or more foods, then tap Next.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
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
            } else {
                ForEach(entries) { entry in
                    if isSelectingMealItems {
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
                    } else {
                        SwipeToDeleteRow(
                            isReordering: draggedEntryID != nil,
                            onDelete: { diary.delete(entryID: entry.id) }
                        ) {
                            DiaryEntryRow(
                                entry: entry,
                                showsReorderHandle: true,
                                onBreakApartMeal: entry.isMeal ? {
                                    withAnimation(.snappy) {
                                        diary.breakApartMeal(entryID: entry.id)
                                    }
                                } : nil
                            )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard !entry.isMeal else { return }
                                    editingEntry = entry
                                }
                                .accessibilityAction(named: "Edit quantity") {
                                    guard !entry.isMeal else { return }
                                    editingEntry = entry
                                }
                                .onDrag {
                                    draggedEntryID = entry.id
                                    return NSItemProvider(object: entry.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: DiaryEntryReorderDropDelegate(
                                        targetEntryID: entry.id,
                                        date: date,
                                        entries: entries,
                                        draggedEntryID: $draggedEntryID,
                                        diary: diary
                                    )
                                )
                        }
                    }
                }
            }
        }
        .dropDestination(for: String.self) { _, _ in
            draggedEntryID = nil
            return true
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
}

private struct DateStrip: View {
    @Binding var dayOffset: Int

    var body: some View {
        HStack(spacing: 8) {
            dayButton(offset: -1, title: "Yesterday")
            dayButton(offset: 0, title: "Today")
            dayButton(offset: 1, title: "Tomorrow")
        }
        .padding(5)
        .background(Color.black.opacity(0.055), in: Capsule())
    }

    private func dayButton(offset: Int, title: String) -> some View {
        Button {
            withAnimation(.snappy) { dayOffset = offset }
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
            .foregroundStyle(dayOffset == offset ? Color.white : AppTheme.ink)
            .background(dayOffset == offset ? AppTheme.ink : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func date(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(calorieProgress.consumed.formatted())
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        if let goal = calorieProgress.goal {
                            Text("/ \(goal.formatted())")
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    Text("calories")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(calorieProgress.accessibilityLabel)
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(AppTheme.coral)
                    .padding(14)
                    .background(AppTheme.coral.opacity(0.12), in: Circle())
            }
            HStack(spacing: 8) {
                macro("Carbs", value: nutrients.carbs, color: AppTheme.carbs)
                macro("Fat", value: nutrients.fat, color: AppTheme.fat)
                macro("Protein", value: nutrients.protein, color: AppTheme.protein)
            }
        }
        .padding(20)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }

    private func macro(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(color).frame(width: 24, height: 4)
            Text("\(value.cleanAmount)g")
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DiaryEntryRow: View {
    let entry: DiaryEntry
    var showsReorderHandle = false
    var onBreakApartMeal: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if !entry.isMeal {
                SourceBadge(source: entry.food.source)
            } else {
                Text("Meal")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.coral)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.coral.opacity(0.12), in: Circle())
                    .accessibilityLabel("Saved meal")
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
            if let onBreakApartMeal {
                Menu {
                    Button("Break apart meal", systemImage: "rectangle.split.3x1", action: onBreakApartMeal)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Meal actions")
            }
            if showsReorderHandle {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Reorder \(entry.food.name)")
                    .accessibilityHint("Touch and hold the row, then drag to change its position")
            }
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

private struct DiaryEntryReorderDropDelegate: DropDelegate {
    let targetEntryID: UUID
    let date: Date
    let entries: [DiaryEntry]
    @Binding var draggedEntryID: UUID?
    let diary: DiaryStore

    func dropEntered(info: DropInfo) {
        guard
            let draggedEntryID,
            draggedEntryID != targetEntryID,
            let sourceIndex = entries.firstIndex(where: { $0.id == draggedEntryID }),
            let targetIndex = entries.firstIndex(where: { $0.id == targetEntryID })
        else { return }

        withAnimation(.snappy) {
            diary.moveEntry(
                draggedEntryID,
                relativeTo: targetEntryID,
                placeAfterTarget: targetIndex > sourceIndex,
                on: date
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedEntryID = nil
        return true
    }
}

private struct SwipeToDeleteRow<Content: View>: View {
    let isReordering: Bool
    let onDelete: () -> Void
    private let content: () -> Content

    @State private var restingOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let actionWidth: CGFloat = 84

    init(
        isReordering: Bool,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isReordering = isReordering
        self.onDelete = onDelete
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: delete) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
            }
            .buttonStyle(.plain)

            content()
                .offset(x: displayedOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .simultaneousGesture(swipeGesture)
        .accessibilityAction(named: "Delete", delete)
        .onChange(of: isReordering) { _, isReordering in
            if isReordering { restingOffset = 0 }
        }
    }

    private var displayedOffset: CGFloat {
        min(0, max(-actionWidth, restingOffset + dragOffset))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .updating($dragOffset) { value, state, _ in
                guard
                    !isReordering,
                    abs(value.translation.width) > abs(value.translation.height)
                else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard
                    !isReordering,
                    abs(value.translation.width) > abs(value.translation.height)
                else { return }

                let projectedOffset = restingOffset + value.predictedEndTranslation.width
                if projectedOffset < -(actionWidth * 1.65) {
                    delete()
                } else {
                    withAnimation(.snappy) {
                        restingOffset = projectedOffset < -(actionWidth / 2) ? -actionWidth : 0
                    }
                }
            }
    }

    private func delete() {
        withAnimation(.snappy) { onDelete() }
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
