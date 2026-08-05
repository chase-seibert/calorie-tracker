import SwiftUI
import UIKit

struct DiaryView: View {
    @EnvironmentObject private var diary: DiaryStore
    let catalog: CatalogStore

    @State private var dayOffset = 0
    @State private var showingFoodPicker = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--show-food-search") || arguments.contains("--show-food-picker")
    }()
    @State private var showingMealName = false
    @State private var showingDeleteConfirmation = false
    @State private var mealName = ""
    @State private var isSelectingMealItems = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var editingEntry: DiaryEntry?
    @State private var isMacroSummaryVisible = true
    @State private var showingTrends = false
    @State private var diaryEntriesHeight: CGFloat = 0
    @State private var foodPickerMode: FoodPickerView.Mode?

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        DateStrip(dayOffset: $dayOffset)
                            .id("date-strip")
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 7)
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
                            foodPickerMode = nil
                            showingFoodPicker = true
                        } label: {
                            Label("Log food", systemImage: "magnifyingglass")
                                .font(.headline)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Capsule())

                        FoodPickerModeStrip(selection: $foodPickerMode) { _ in
                            showingFoodPicker = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 0)
                    .background(.ultraThinMaterial.opacity(0.78))
                }
            }
            .sheet(isPresented: $showingFoodPicker) {
                FoodPickerView(date: date, catalog: catalog, initialMode: foodPickerMode)
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
        }
    }

    @ViewBuilder
    private var entrySection: some View {
        let entries = diary.entries(on: date)
        Section {
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
                        editingEntry = entry
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
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }
}

private struct CalorieProgressIcon: View {
    let progress: Double?
    let remaining: Int?
    let over: Int?

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

            if let over, over > 0 {
                Text("\(over.formatted()) over")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize()
            } else if let remaining {
                Text("\(remaining.formatted()) left")
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
                CalorieProgressIcon(
                    progress: calorieProgress.fraction,
                    remaining: calorieProgress.remaining,
                    over: calorieProgress.over
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
            true
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
