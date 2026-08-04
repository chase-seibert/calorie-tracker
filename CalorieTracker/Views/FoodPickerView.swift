import SwiftUI
import UIKit

struct FoodPickerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case suggested = "For You"
        case recent = "Recent"
        case frequent = "Frequent"
        case favorites = "Favorites"
        case meals = "Meals"
        case scan = "Scan"

        var id: String { rawValue }
    }

    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let catalog: CatalogStore

    @State private var mode: Mode = .suggested
    @State private var selectedFood: Food?
    @State private var query = ProcessInfo.processInfo.arguments.contains("--show-food-search") ? "banana" : ""
    @State private var results: [Food] = []
    @State private var isSearching = false
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchControls
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    modeStrip
                }
                Divider()
                Group {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SearchResultsList(
                            query: query,
                            results: results,
                            isSearching: isSearching,
                            onQuickLog: quickLog,
                            onEdit: { selectedFood = $0 }
                        )
                    } else {
                        switch mode {
                        case .suggested:
                            QuickFoodList(
                                title: nil,
                                emptyMessage: "Your recent, frequent, and favorite foods will appear here.",
                                foods: diary.suggestedFoods,
                                onQuickLog: quickLog,
                                onEdit: { selectedFood = $0 }
                            )
                        case .recent:
                            QuickFoodList(
                                title: "Logged recently",
                                emptyMessage: "Foods you log will appear here.",
                                foods: diary.recentFoods,
                                onQuickLog: quickLog,
                                onEdit: { selectedFood = $0 }
                            )
                        case .frequent:
                            QuickFoodList(
                                title: "Most used · 90 days",
                                emptyMessage: "Your most-used foods will appear here.",
                                foods: diary.frequentFoods,
                                onQuickLog: quickLog,
                                onEdit: { selectedFood = $0 }
                            )
                        case .favorites:
                            QuickFoodList(
                                title: "Favorites",
                                emptyMessage: "Star any food to keep it here.",
                                foods: diary.document.favorites,
                                onQuickLog: quickLog,
                                onEdit: { selectedFood = $0 }
                            )
                        case .meals:
                            MealsList { meal in
                                diary.logMeal(meal, on: date)
                                dismiss()
                            }
                        case .scan:
                            BarcodeLookup(catalog: catalog, onSelect: { selectedFood = diary.displayedFood($0) })
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.background)
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { food in
                QuantityEditor(food: food, date: date)
                    .presentationDetents([.medium])
            }
            .task {
                try? await Task.sleep(for: .milliseconds(180))
                searchIsFocused = true
            }
            .task(id: query) {
                let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedQuery.isEmpty else {
                    results = []
                    isSearching = false
                    return
                }
                isSearching = true
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                let personalResults = diary.searchPersonalFoods(normalizedQuery)
                let bundledResults = catalog.searchAll(normalizedQuery)
                var seen = Set<String>()
                results = (Array(personalResults.prefix(10)) + bundledResults + Array(personalResults.dropFirst(10)))
                    .filter { seen.insert($0.id).inserted }
                    .prefix(50)
                    .map(diary.displayedFood)
                isSearching = false
            }
        }
    }

    private var searchControls: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search foods", text: $query)
                .focused($searchIsFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var modeStrip: some View {
        FlowLayout(spacing: 6) {
            ForEach(Mode.allCases) { item in
                Button {
                    withAnimation(.snappy) {
                        mode = item
                        searchIsFocused = false
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.caption.weight(.semibold))
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .foregroundStyle(mode == item ? AppTheme.selectedText : AppTheme.ink)
                        .background(mode == item ? AppTheme.ink : AppTheme.controlFill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func quickLog(_ food: Food) {
        diary.quickLog(food, on: date)
        dismiss()
    }
}

private struct QuickFoodList: View {
    @EnvironmentObject private var diary: DiaryStore
    let title: String?
    let emptyMessage: String
    let foods: [Food]
    let onQuickLog: (Food) -> Void
    let onEdit: (Food) -> Void

    var body: some View {
        if foods.isEmpty {
            ContentUnavailableView(title ?? "No suggestions yet", systemImage: "fork.knife.circle", description: Text(emptyMessage))
        } else {
            List {
                Section {
                    ForEach(foods) { food in
                        FoodResultRow(
                            food: food,
                            preference: diary.preference(for: food),
                            actionTitle: "Add",
                            action: { onQuickLog(food) }
                        )
                            .contentShape(Rectangle())
                            .onTapGesture { onEdit(food) }
                    }
                } header: {
                    if let title { Text(title) }
                } footer: {
                    Text("Tap + to reuse your last quantity. Tap the row to change it.")
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct FoodResultRow: View {
    let food: Food
    var preference: QuantityPreference? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            SourceBadge(source: food.source)
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let brand = food.displayBrand { Text(brand + " ·") }
                    Text(nutritionDescription)
                }
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, systemImage: "plus", action: action)
                    .labelStyle(.iconOnly)
                    .font(.headline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("\(actionTitle) \(food.name)")
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var nutritionDescription: String {
        guard let preference else {
            return "\(Int(food.nutrients.calories.rounded())) cal / \(food.baseAmountGrams.cleanAmount)g"
        }
        let nutrients = food.nutrients(
            for: preference.amount,
            unit: preference.unit,
            portionID: preference.portionID
        )
        return "\(Int(nutrients.calories.rounded())) cal / \(quantityDescription(preference))"
    }

    private func quantityDescription(_ preference: QuantityPreference) -> String {
        switch preference.unit {
        case .grams, .ounces:
            "\(preference.amount.cleanAmount) \(preference.unit.rawValue)"
        case .serving:
            "\(preference.amount.cleanAmount) \(food.portion(id: preference.portionID)?.label ?? "serving")"
        }
    }
}

private struct SearchResultsList: View {
    @EnvironmentObject private var diary: DiaryStore
    let query: String
    let results: [Food]
    let isSearching: Bool
    let onQuickLog: (Food) -> Void
    let onEdit: (Food) -> Void

    var body: some View {
        if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                Section {
                    ForEach(results) { food in
                        FoodResultRow(
                            food: food,
                            preference: diary.preference(for: food),
                            actionTitle: "Quick add",
                            action: { onQuickLog(food) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onEdit(food) }
                    }
                } footer: {
                    Text("Tap + to log the displayed quantity. Tap the row to change it.")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private enum QuantityUnitChoice: Hashable {
    case ounces
    case grams
    case portion(String)
}

struct QuantityEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var food: Food
    let date: Date
    private let entryID: UUID?

    @State private var amount: Double
    @State private var unitChoice: QuantityUnitChoice
    @State private var showingNameEditor = false
    @FocusState private var amountIsFocused: Bool

    init(food: Food, date: Date) {
        _food = State(initialValue: food)
        self.date = date
        entryID = nil
        _amount = State(initialValue: 1)
        _unitChoice = State(initialValue: .ounces)
    }

    init(entry: DiaryEntry) {
        _food = State(initialValue: entry.food)
        date = entry.date
        entryID = entry.id
        _amount = State(initialValue: entry.amount)
        switch entry.unit {
        case .ounces:
            _unitChoice = State(initialValue: .ounces)
        case .grams:
            _unitChoice = State(initialValue: .grams)
        case .serving:
            if let portion = entry.food.portion(id: entry.portionID) {
                _unitChoice = State(initialValue: .portion(portion.id))
            } else {
                _unitChoice = State(initialValue: .ounces)
            }
        }
    }

    private var availableChoices: [QuantityUnitChoice] {
        [.ounces, .grams] + food.availablePortions.map { .portion($0.id) }
    }

    private var selectedUnit: LogUnit {
        switch unitChoice {
        case .ounces: .ounces
        case .grams: .grams
        case .portion: .serving
        }
    }

    private var selectedPortionID: String? {
        guard case let .portion(id) = unitChoice else { return nil }
        return id
    }

    private var preview: MacroNutrients {
        food.nutrients(for: amount, unit: selectedUnit, portionID: selectedPortionID)
    }

    private var currentPreference: QuantityPreference {
        QuantityPreference(amount: amount, unit: selectedUnit, portionID: selectedPortionID)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    FoodResultRow(food: food)
                    Button("Rename food", systemImage: "pencil") {
                        showingNameEditor = true
                    }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(AppTheme.coral)
                    .frame(width: 44, height: 44)
                    .accessibilityHint("Choose the name used throughout the app")
                }
                HStack(spacing: 12) {
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .focused($amountIsFocused)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .padding(12)
                        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))
                        .onSubmit(save)
                        .onChange(of: amountIsFocused) { _, isFocused in
                            if isFocused { selectAllAmount() }
                        }
                    Picker("Unit", selection: $unitChoice) {
                        ForEach(availableChoices, id: \.self) { choice in
                            Text(label(for: choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack {
                    nutrient("Calories", preview.calories, suffix: "")
                    nutrient("Carbs", preview.carbs, suffix: "g")
                    nutrient("Fat", preview.fat, suffix: "g")
                    nutrient("Protein", preview.protein, suffix: "g")
                }
                Button(action: save) {
                    Text(entryID == nil ? "Add \(Int(preview.calories.rounded())) calories" : "Save quantity")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(amount <= 0)
                Spacer()
            }
            .padding(18)
            .background(AppTheme.background)
            .navigationTitle(entryID == nil ? "Quantity" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(diary.isFavorite(food) ? "Unfavorite" : "Favorite", systemImage: diary.isFavorite(food) ? "star.fill" : "star") {
                        diary.toggleFavorite(food, preference: currentPreference)
                    }
                    .labelStyle(.iconOnly)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Save", action: save)
                        .disabled(amount <= 0)
                }
            }
            .sheet(isPresented: $showingNameEditor) {
                FoodNameEditor(food: food) { name in
                    guard diary.renameFood(foodID: food.id, name: name) else { return }
                    food = diary.displayedFood(food)
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                guard entryID == nil else { return }
                let preference = diary.preference(for: food)
                amount = preference.amount
                switch preference.unit {
                case .ounces:
                    unitChoice = .ounces
                case .grams:
                    unitChoice = .grams
                case .serving:
                    if let portion = food.portion(id: preference.portionID) {
                        unitChoice = .portion(portion.id)
                    } else {
                        unitChoice = .ounces
                    }
                }
            }
            .onDisappear {
                if entryID == nil, diary.isFavorite(food) {
                    diary.rememberPreference(currentPreference, for: food)
                }
            }
        }
    }

    private func label(for choice: QuantityUnitChoice) -> String {
        switch choice {
        case .ounces: "ounces"
        case .grams: "grams"
        case let .portion(id):
            food.portion(id: id)?.label ?? "serving"
        }
    }

    private func save() {
        guard amount > 0 else { return }
        if let entryID {
            diary.updateEntry(
                entryID: entryID,
                amount: amount,
                unit: selectedUnit,
                portionID: selectedPortionID
            )
        } else {
            diary.log(
                food,
                amount: amount,
                unit: selectedUnit,
                portionID: selectedPortionID,
                on: date
            )
        }
        dismiss()
    }

    @MainActor
    private func selectAllAmount() {
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(
                #selector(UIResponder.selectAll(_:)),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

    private func nutrient(_ title: String, _ value: Double, suffix: String) -> some View {
        VStack(spacing: 3) {
            Text(value.cleanAmount + suffix).font(.subheadline.weight(.bold).monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FoodNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let onApply: (String) -> Void

    @State private var name: String
    @State private var hasFinished = false

    init(food: Food, onApply: @escaping (String) -> Void) {
        self.food = food
        self.onApply = onApply
        _name = State(initialValue: food.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food name", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("This name is saved when you leave this editor and will be used in the diary, favorites, and future searches.")
                }
            }
            .navigationTitle("Rename food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        hasFinished = true
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: applyAndDismiss)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onDisappear {
                guard !hasFinished else { return }
                hasFinished = true
                onApply(name)
            }
        }
    }

    private func applyAndDismiss() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        hasFinished = true
        onApply(name)
        dismiss()
    }
}

private struct MealsList: View {
    @EnvironmentObject private var diary: DiaryStore
    let onQuickLog: (SavedMeal) -> Void

    var body: some View {
        if diary.document.meals.isEmpty {
            ContentUnavailableView(
                "No saved meals",
                systemImage: "square.stack.3d.up",
                description: Text("From the diary, log a combination and choose Save meal.")
            )
        } else {
            List {
                ForEach(diary.document.meals) { meal in
                    Button {
                        onQuickLog(meal)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(meal.name).font(.body.weight(.semibold))
                                Text("\(meal.items.count) items · \(Int(meal.items.reduce(0) { $0 + $1.food.nutrients(for: $1.amount, unit: $1.unit, portionID: $1.portionID).calories }.rounded())) cal")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { diary.deleteMeal(meal) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = rows(for: subviews, width: width)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> (height: CGFloat, rows: Int) {
        var x: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowCount = subviews.isEmpty ? 0 : 1

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
                rowCount += 1
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (height + rowHeight, rowCount)
    }
}

private struct BarcodeLookup: View {
    let catalog: CatalogStore
    let onSelect: (Food) -> Void

    @State private var barcode = ""
    @State private var notFound = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BarcodeScanner { code in
                    barcode = code
                    lookup()
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 22))

                Text("Point the camera at a UPC or EAN barcode.")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack {
                    TextField("Enter barcode", text: $barcode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Look up") { lookup() }
                        .buttonStyle(.borderedProminent)
                }
                if notFound {
                    Label("No local match. Add it as a custom food.", systemImage: "exclamationmark.magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private func lookup() {
        if let food = catalog.food(barcode: barcode) {
            notFound = false
            onSelect(food)
        } else {
            notFound = true
        }
    }
}
