import SwiftUI

/// One composition screen, with an explicit destination for the final commit.
struct MealDetailView: View {
    enum Context {
        case log(SavedMeal, Date, (QuantityPreference, QuantityPreference?) -> Void)
        case logged(DiaryEntry)
        case template(SavedMeal?)
        case imported(CustomMealFile, Date, CustomMealImportView.Source, (() -> Void)?)
        case component(SavedMeal, ([MealItem]) -> Void)
    }
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let context: Context
    let catalog: CatalogStore
    private let initialItems: [MealItem]
    @State private var name: String
    @State private var items: [MealItem]
    @State private var amount: Double
    @State private var processed: Bool?
    @State private var red: Bool?
    @State private var showingSearch = false
    @State private var editingQuantityItem: MealItem?
    @State private var editingFoodItem: MealItem?
    @State private var pendingRemoval: MealItem?
    @State private var openSwipeRowID: UUID?
    @State private var showingNameEditor = false
    @State private var saveForReuse = false
    @State private var isCommitting = false

    init(context: Context, catalog: CatalogStore) {
        self.context = context; self.catalog = catalog
        let meal: SavedMeal
        var amount = 1.0
        switch context {
        case .log(let value, _, _), .component(let value, _): meal = value
        case .template(let value): meal = value ?? SavedMeal(id: UUID(), name: "", items: [])
        case .imported(let file, _, _, _): meal = file.makeMeal()
        case .logged(let entry):
            amount = entry.amount
            meal = SavedMeal(id: entry.savedMealID ?? UUID(), name: entry.food.name,
                items: (entry.mealItems ?? []).map { var item = $0; item.amount /= max(entry.amount, 0.001); return item },
                containsProcessedMeat: entry.processedMeatOverride, containsRedMeat: entry.redMeatOverride,
                notes: entry.mealNotes)
        }
        initialItems = meal.items
        _name = State(initialValue: meal.name); _items = State(initialValue: meal.items)
        _amount = State(initialValue: amount)
        _processed = State(initialValue: meal.containsProcessedMeat); _red = State(initialValue: meal.containsRedMeat)
    }

    private var targetDate: Date {
        switch context {
        case .log(_, let date, _), .imported(_, let date, _, _): date
        case .logged(let entry): entry.date
        default: Date()
        }
    }
    private var notes: String? {
        switch context {
        case .log(let meal, _, _), .component(let meal, _): meal.notes
        case .template(let meal): meal?.notes
        case .imported(let file, _, _, _): file.notes
        case .logged(let entry): entry.mealNotes
        }
    }
    private var title: String {
        switch context {
        case .log: "Log meal"
        case .logged: "Edit meal"
        case .template(let meal): meal == nil ? "Add Saved Meal" : "Edit Saved Meal"
        case .imported(_, _, let source, _): source.navigationTitle
        case .component: "Add meal foods"
        }
    }
    private var actionTitle: String {
        switch context {
        case .logged: "Save changes"
        case .template: "Save Saved Meal"
        case .component: "Add to parent"
        default: "Log Meal"
        }
    }
    private var scaledItems: [MealItem] {
        if case .logged(let entry) = context, items == initialItems, amount == entry.amount {
            return entry.mealItems ?? []
        }
        return items.map { var item = $0; item.amount *= amount; return item }
    }
    private var totals: MacroNutrients {
        if case .logged(let entry) = context, items == initialItems {
            return entry.nutrients.scaled(by: amount / max(entry.amount, 0.001))
        }
        return scaledItems.reduce(.zero) { $0 + $1.food.nutrients(for: $1.amount, unit: $1.unit, portionID: $1.portionID) }
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 120
            && amount.isFinite && amount > 0 && !items.isEmpty && items.count <= 50
            && items.allSatisfy { $0.amount.isFinite && $0.amount > 0 }
    }
    private var excludedMealIDs: Set<UUID> {
        switch context {
        case .template(let meal): meal.map { [$0.id] } ?? []
        case .log(let meal, _, _), .component(let meal, _): [meal.id]
        case .logged(let entry): entry.savedMealID.map { [$0] } ?? []
        default: []
        }
    }

    var body: some View {
        NavigationStack {
            CustomizationScreen(title: name.isEmpty ? title : name, subtitle: "", headerIcon: "fork.knife.circle.fill",
                nutrients: totals,
                actionTitle: actionTitle, actionID: "meal-detail-save", canSave: canSave && !isCommitting && !diary.isSaving,
                action: save, menu: {
                    if let meal = favoriteMeal {
                        Button(diary.isFavorite(meal) ? "Unfavorite" : "Favorite", systemImage: diary.isFavorite(meal) ? "star.fill" : "star") {
                            diary.run { try await diary.toggleFavorite(meal) }
                        }
                    }
                    Button("Rename") { showingNameEditor = true }
                    Divider()
                    if case .logged(let entry) = context {
                        Button("Break apart meal", systemImage: "rectangle.split.3x1") {
                            guard !diary.isSaving else { return }
                            diary.run { try await diary.breakApartMeal(entryID: entry.id); dismiss() }
                        }
                    }
                }, quantity: { mealQuantityControls }) {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let notes { Text(notes).font(.subheadline).foregroundStyle(AppTheme.muted) }
                        if case .template = context { Text("Saving this template also refreshes its linked diary entries.").font(.caption).foregroundStyle(AppTheme.muted) }
                        if case .logged = context { Text("Changes apply to this logged entry only.").font(.caption).foregroundStyle(AppTheme.muted) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FOODS PER MEAL").font(.caption.weight(.bold)).foregroundStyle(AppTheme.muted)
                        VStack(spacing: 12) {
                            ForEach($items) { item in
                                ZStack(alignment: .trailing) {
                                    Button {
                                        pendingRemoval = item.wrappedValue
                                        openSwipeRowID = nil
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 82).frame(maxHeight: .infinity)
                                            .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                                    }
                                    .accessibilityIdentifier("meal-component-delete-" + item.wrappedValue.food.sourceID)
                                    .opacity(openSwipeRowID == item.wrappedValue.id ? 1 : 0)
                                    .allowsHitTesting(openSwipeRowID == item.wrappedValue.id)
                                    .zIndex(openSwipeRowID == item.wrappedValue.id ? 1 : -1)

                                    VStack(alignment: .leading, spacing: 8) {
                                        MealItemRow(item: item.wrappedValue)
                                        Button("Customize") { customizeMealItem(item.wrappedValue) }
                                            .font(.subheadline.weight(.semibold)).underline().foregroundStyle(AppTheme.coral)
                                            .accessibilityIdentifier("meal-component-edit-" + item.wrappedValue.food.sourceID)
                                    }
                                    .padding(16)
                                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.controlFill, lineWidth: 1))
                                    .offset(x: openSwipeRowID == item.wrappedValue.id ? -90 : 0)
                                    .zIndex(openSwipeRowID == item.wrappedValue.id ? 0 : 1)
                                    .contentShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("meal-component-row-" + item.wrappedValue.food.sourceID)
                                .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    if value.translation.width < -45 {
                                        withAnimation(.easeOut(duration: 0.18)) { openSwipeRowID = item.wrappedValue.id }
                                    } else if value.translation.width > 35 {
                                        withAnimation(.easeOut(duration: 0.18)) { openSwipeRowID = nil }
                                    }
                                })
                            }
                        }
                        Button { showingSearch = true } label: {
                            Label("Add another food", systemImage: "plus").font(.body.weight(.semibold)).foregroundStyle(AppTheme.coral)
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(.horizontal, 16)
                                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.controlFill, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityIdentifier("meal-detail-add-food")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MEAT TRACKING").font(.caption.weight(.bold)).foregroundStyle(AppTheme.muted)
                        FoodMeatFields(name: name, processed: $processed, red: $red, derivesFromIngredients: true,
                            automaticProcessed: classification(\.processedMeatOverride, food: \.containsProcessedMeat),
                            automaticRed: classification(\.redMeatOverride, food: \.containsRedMeat))
                    }
                    if case .imported = context {
                        Toggle("Save to Saved meals", isOn: $saveForReuse)
                        Text(saveForReuse ? "Log this meal and save it for reuse." : "Log this meal once; keep its ingredient snapshots in the diary.")
                            .font(.caption).foregroundStyle(AppTheme.muted)
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                FoodPickerView(date: targetDate, catalog: catalog, componentSelection: ComponentSelectionContext(
                    excludedMealIDs: excludedMealIDs, onSelect: { items += $0 }))
            }
            .sheet(isPresented: $showingNameEditor) {
                CustomizationNameEditor(name: name, title: "Edit meal name") { name = $0 }
            }
            .sheet(item: $editingQuantityItem) { item in
                MealComponentQuantityEditor(item: item) { updated in
                    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = updated }
                    editingQuantityItem = nil
                }
            }
            .fullScreenCover(item: $editingFoodItem) { item in
                FoodDetailView(item: item, catalog: catalog, date: targetDate) { result in
                    if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = result }
                    editingFoodItem = nil
                }
            }
            .alert("Remove \(pendingRemoval?.food.name ?? "food")?", isPresented: Binding(
                get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
                Button("Remove", role: .destructive) {
                    guard let item = pendingRemoval else { return }
                    items.removeAll { $0.id == item.id }
                    pendingRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingRemoval = nil }
            } message: { Text("This food will be removed from this meal when you save.") }
        }
        .draftSaveError()
    }

    private var mealQuantityControls: some View {
        CustomizationQuantityControls(amount: $amount, identifier: "meal-detail-quantity") {
            Text("meal").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.coral)
                .padding(.horizontal, 9).frame(minWidth: 76, minHeight: 40)
                .background(AppTheme.coral.opacity(0.10), in: Capsule())
            Spacer(minLength: 0)
        }.disabled(isTemplate)
    }
    private var isTemplate: Bool { if case .template = context { return true }; return false }

    private func customizeMealItem(_ item: MealItem) {
        if case .imported = context { editingFoodItem = item }
        else { editingQuantityItem = item }
    }

    private var favoriteMeal: SavedMeal? {
        switch context {
        case .log(let meal, _, _): meal
        case .logged(let entry): diary.document.meals.first { $0.id == entry.savedMealID }
        default: nil
        }
    }
    private func classification(_ override: KeyPath<MealItem, Bool?>, food: KeyPath<Food, Bool?>) -> Bool? {
        let values = items.map { $0[keyPath: override] ?? $0.food[keyPath: food] }
        if values.contains(true) { return true }
        return values.allSatisfy { $0 == false } ? false : nil
    }
    private func save() {
        guard canSave, !isCommitting, !diary.isSaving else { return }
        if case .component(_, let onSave) = context {
            // Each addition gets its own IDs, even when adding the same saved meal twice.
            onSave(scaledItems.map { item in
                MealItem(id: UUID(), food: item.food, amount: item.amount, unit: item.unit, portionID: item.portionID,
                    meatServingsOverride: item.meatServingsOverride, foodConfigurationSnapshot: item.foodConfigurationSnapshot,
                    notes: item.notes, processedMeatOverride: item.processedMeatOverride, redMeatOverride: item.redMeatOverride)
            })
            dismiss(); return
        }
        isCommitting = true
        diary.run {
            defer { isCommitting = false }
            switch context {
            case .logged(let entry):
                try await diary.updateMealDraft(original: entry, name: name, amount: amount, items: scaledItems, processed: processed, red: red)
            case .template(let meal):
                if let meal {
                    guard try await diary.updateSavedMeal(mealID: meal.id, name: name, items: items,
                        meatOverrides: FoodMeatOverrides(processed: processed, red: red)) else { throw FoodDraftError.missingEntry }
                } else {
                    guard try await diary.saveMeal(name: name, items: items, containsProcessedMeat: processed, containsRedMeat: red) != nil
                    else { throw FoodDraftError.invalidDraft }
                }
            case .log(let original, let date, let onLogged):
                if name == original.name && items == original.items && processed == original.containsProcessedMeat && red == original.containsRedMeat {
                    try await diary.logMeal(original, amount: amount, on: date, allowCheatDay: true)
                } else {
                    let meal = SavedMeal(id: UUID(), name: name, items: items,
                        containsProcessedMeat: processed, containsRedMeat: red, notes: notes)
                    _ = try await diary.logImportedMeal(meal, saveForReuse: false, amount: amount, on: date, allowCheatDay: true)
                }
                onLogged(QuantityPreference(amount: amount, unit: .serving), nil)
            case .imported(_, let date, let source, let onLogged):
                let meal = SavedMeal(id: UUID(), name: name, items: items,
                    containsProcessedMeat: processed, containsRedMeat: red, origin: .imported, notes: notes)
                let logged = try await diary.logImportedMeal(meal, saveForReuse: saveForReuse, amount: amount, on: date, allowCheatDay: true)
                AppAnalytics.capture("food_log.completed", properties: FoodLogAnalytics.mealProperties(meal: logged,
                    method: source.analyticsMethod, mode: "import", isFavorite: saveForReuse && diary.isFavorite(logged), foodKind: "imported", savedForReuse: saveForReuse))
                onLogged?()
            case .component: break
            }
            dismiss()
        }
    }
}

struct MealComponentQuantityEditor: View {
    private enum UnitChoice: Hashable {
        case serving(String)
        case grams
        case ounces
    }

    @Environment(\.dismiss) private var dismiss
    let item: MealItem
    let onSave: (MealItem) -> Void
    @State private var amount: Double
    @State private var choice: UnitChoice

    init(item: MealItem, onSave: @escaping (MealItem) -> Void) {
        self.item = item
        self.onSave = onSave
        _amount = State(initialValue: item.amount)
        switch item.unit {
        case .grams: _choice = State(initialValue: .grams)
        case .ounces: _choice = State(initialValue: .ounces)
        case .serving: _choice = State(initialValue: .serving(item.portionID ?? item.food.availablePortions.first?.id ?? ""))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(item.food.name) {
                    TextField("Quantity", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("meal-component-quantity-value")
                    Picker("Unit", selection: $choice) {
                        ForEach(item.food.availablePortions, id: \.id) { portion in
                            Text(portion.label).tag(UnitChoice.serving(portion.id))
                        }
                        Text("Grams").tag(UnitChoice.grams)
                        Text("Ounces").tag(UnitChoice.ounces)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("meal-component-quantity-unit")
                }
            }
            .navigationTitle("Customize quantity").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard amount.isFinite, amount > 0 else { return }
                        var updated = item
                        switch choice {
                        case .serving(let portionID):
                            updated.unit = .serving
                            updated.portionID = portionID
                            updated.amount = max(amount, 0.001)
                        case .grams:
                            updated.unit = .grams
                            updated.portionID = nil
                            updated.amount = max(amount, 0.001)
                        case .ounces:
                            updated.unit = .ounces
                            updated.portionID = nil
                            updated.amount = max(amount, 0.001)
                        }
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(!amount.isFinite || amount <= 0)
                    .accessibilityIdentifier("meal-component-quantity-save")
                }
            }
        }
        .presentationDetents([.height(290)])
    }
}

/// Imported nutrition definitions retain their own fields within the shared food detail flow.
struct ImportedDefinitionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let item: MealItem
    let onSave: (MealItem) -> Void
    @State private var definition: CustomFoodDefinition
    init(item: MealItem, onSave: @escaping (MealItem) -> Void) {
        self.item = item; self.onSave = onSave
        let food = item.food
        _definition = State(initialValue: CustomFoodDefinition(name: food.name,
            servingDescription: food.portion(id: "imported-serving")?.label ?? "serving", servingGrams: food.baseAmountGrams,
            nutrition: .init(calories: food.nutrients.calories, carbohydratesGrams: food.nutrients.carbs,
                fatGrams: food.nutrients.fat, proteinGrams: food.nutrients.protein, fiberGrams: food.nutrients.fiber),
            notes: item.notes, containsProcessedMeat: food.containsProcessedMeat, containsRedMeat: food.containsRedMeat))
    }
    var body: some View {
        NavigationStack {
            Form { ImportedFoodFields(food: $definition) }
                .navigationTitle("Ingredient definition")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use changes") {
                            var result = item
                            result.food = definition.makeFood(sourceID: item.food.sourceID)
                            result.notes = definition.notes
                            onSave(result); dismiss()
                        }.disabled((try? definition.validate()) == nil)
                    }
                }
        }
    }
}
