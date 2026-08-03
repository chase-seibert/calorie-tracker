import SwiftUI

struct FoodPickerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case frequent = "Frequent"
        case favorites = "Favorites"
        case meals = "Meals"
        case search = "Search"
        case scan = "Scan"
        case custom = "Custom"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .recent: "clock"
            case .frequent: "repeat"
            case .favorites: "star"
            case .meals: "square.stack.3d.up"
            case .search: "magnifyingglass"
            case .scan: "barcode.viewfinder"
            case .custom: "square.and.pencil"
            }
        }
    }

    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let catalog: CatalogStore

    @State private var mode: Mode = ProcessInfo.processInfo.arguments.contains("--show-food-search") ? .search : .recent
    @State private var selectedFood: Food?
    @State private var addedMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modeStrip
                Divider()
                Group {
                    switch mode {
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
                        MealsList(date: date)
                    case .search:
                        CatalogSearch(catalog: catalog, onSelect: { selectedFood = $0 })
                    case .scan:
                        BarcodeLookup(catalog: catalog, onSelect: { selectedFood = $0 })
                    case .custom:
                        CustomFoodForm(date: date)
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
            .overlay(alignment: .bottom) {
                if let addedMessage {
                    Label(addedMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppTheme.ink, in: Capsule())
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(item: $selectedFood) { food in
                QuantityEditor(food: food, date: date)
                    .presentationDetents([.medium])
            }
        }
    }

    private var modeStrip: some View {
        FlowLayout(spacing: 8) {
            ForEach(Mode.allCases) { item in
                Button {
                    withAnimation(.snappy) { mode = item }
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.caption.weight(.semibold))
                        .fixedSize()
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .foregroundStyle(mode == item ? Color.white : AppTheme.ink)
                        .background(mode == item ? AppTheme.ink : Color.black.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func quickLog(_ food: Food) {
        diary.quickLog(food, on: date)
        withAnimation(.spring) { addedMessage = "Added \(food.name)" }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { addedMessage = nil }
        }
    }
}

private struct QuickFoodList: View {
    @EnvironmentObject private var diary: DiaryStore
    let title: String
    let emptyMessage: String
    let foods: [Food]
    let onQuickLog: (Food) -> Void
    let onEdit: (Food) -> Void

    var body: some View {
        if foods.isEmpty {
            ContentUnavailableView(title, systemImage: "fork.knife.circle", description: Text(emptyMessage))
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
                    Text(title)
                } footer: {
                    Text("Tap Add to reuse your last quantity. Tap the row to change it.")
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
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
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

private struct CatalogSearch: View {
    @EnvironmentObject private var diary: DiaryStore
    let catalog: CatalogStore
    let onSelect: (Food) -> Void

    @State private var query = ProcessInfo.processInfo.arguments.contains("--show-food-search") ? "banana" : ""
    @State private var scope: CatalogScope = .usda
    @State private var results: [Food] = []

    var body: some View {
        VStack(spacing: 10) {
            Picker("Source", selection: $scope) {
                ForEach(CatalogScope.allCases) { Text($0.source.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(scope.title)", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)

            if scope == .myFitnessPal, diary.document.importedFoods.isEmpty {
                ContentUnavailableView(
                    "Import not added yet",
                    systemImage: "square.and.arrow.down",
                    description: Text("Import your MyFitnessPal CSV from Settings, then search it here.")
                )
            } else if results.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { food in
                    FoodResultRow(food: food, preference: diary.preference(for: food))
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(food) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .task(id: query + scope.rawValue) {
            try? await Task.sleep(for: .milliseconds(140))
            if scope == .myFitnessPal {
                results = diary.searchPersonalFoods(query)
            } else {
                results = catalog.search(query, source: scope.source)
            }
        }
    }
}

private enum QuantityUnitChoice: Hashable {
    case ounces
    case grams
    case portion(String)
}

private struct QuantityEditor: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let date: Date

    @State private var amount: Double
    @State private var unitChoice: QuantityUnitChoice

    init(food: Food, date: Date) {
        self.food = food
        self.date = date
        _amount = State(initialValue: 1)
        _unitChoice = State(initialValue: .ounces)
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
                FoodResultRow(food: food)
                HStack(spacing: 12) {
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .padding(12)
                        .background(Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
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
                Button {
                    diary.log(
                        food,
                        amount: amount,
                        unit: selectedUnit,
                        portionID: selectedPortionID,
                        on: date
                    )
                    dismiss()
                } label: {
                    Text("Add \(Int(preview.calories.rounded())) calories")
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
            .navigationTitle("Quantity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(diary.isFavorite(food) ? "Unfavorite" : "Favorite", systemImage: diary.isFavorite(food) ? "star.fill" : "star") {
                        diary.toggleFavorite(food, preference: currentPreference)
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .onAppear {
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
                if diary.isFavorite(food) {
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

    private func nutrient(_ title: String, _ value: Double, suffix: String) -> some View {
        VStack(spacing: 3) {
            Text(value.cleanAmount + suffix).font(.subheadline.weight(.bold).monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MealsList: View {
    @EnvironmentObject private var diary: DiaryStore
    let date: Date

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
                        diary.logMeal(meal, on: date)
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

private struct CustomFoodForm: View {
    @EnvironmentObject private var diary: DiaryStore
    let date: Date

    @State private var name = ""
    @State private var brand = ""
    @State private var servingGrams = 100.0
    @State private var calories = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var protein = 0.0
    @State private var saved = false

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $name)
                TextField("Brand (optional)", text: $brand)
                numberField("Serving weight", value: $servingGrams, suffix: "g")
            }
            Section("Per serving") {
                numberField("Calories", value: $calories, suffix: "cal")
                numberField("Carbohydrates", value: $carbs, suffix: "g")
                numberField("Fat", value: $fat, suffix: "g")
                numberField("Protein", value: $protein, suffix: "g")
            }
            Button {
                let food = diary.addCustomFood(
                    name: name,
                    brand: brand,
                    calories: calories,
                    carbs: carbs,
                    fat: fat,
                    protein: protein,
                    servingGrams: servingGrams
                )
                diary.log(food, amount: 1, unit: .serving, on: date)
                saved = true
            } label: {
                Label(saved ? "Added" : "Save and add", systemImage: saved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || servingGrams <= 0)
        }
        .scrollContentBackground(.hidden)
    }

    private func numberField(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(suffix).foregroundStyle(.secondary)
        }
    }
}
