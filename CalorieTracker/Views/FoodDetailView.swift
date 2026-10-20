import SwiftUI
import UIKit

private struct ChaseFoodOptionGroup: Identifiable {
    let name: String
    let selectionMode: String
    let options: [ChaseFoodOption]

    var id: String { name }
}

struct FoodCustomizationView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var food: Food
    let catalog: CatalogStore
    let date: Date
    let initialConfiguration: SavedFoodConfiguration?
    @State private var selectedOptionIDs: Set<String>
    @State private var originalEntry: DiaryEntry?
    private let originalComponent: MealItem?
    private let componentActionTitle: String
    private let onComponentSaved: ((MealItem) -> Void)?
    private let onLogged: (QuantityPreference, QuantityPreference?) -> Void
    @State private var extraComponents: [MealItem]
    @State private var optionDefinitions: [ChaseFoodOption]
    @State private var preservesLegacySnapshot: Bool
    @State private var rebuiltLegacyValues = false
    @State private var isCommitting = false
    @State private var showingDefinitionEditor = false
    @State private var notes: String?
    @State private var didLoadPreference = false
    @State private var initialQuantityPreference: QuantityPreference?
    @State private var showingNameEditor = false
    @State private var editingComponent: MealItem?
    @State private var selectedVariationID: UUID?
    @State private var confirmingVariationDeletion = false
    @State private var processedMeatOverride: Bool?
    @State private var redMeatOverride: Bool?
    @State private var portionID: String
    @State private var amount = 1.0
    @State private var unitChoice: QuantityUnitChoice
    @State private var suggestedChanges = ""
    @State private var showingIngredientSearch = false
    @State private var selectedCompanionFoodIDs: Set<String> = []
    @State private var removedLegacyBurgerFries = false

    init(food: Food, catalog: CatalogStore, date: Date, initialConfiguration: SavedFoodConfiguration? = nil,
         entry: DiaryEntry? = nil, component: MealItem? = nil, isNewComponent: Bool = false, onComponentSaved: ((MealItem) -> Void)? = nil,
         onLogged: @escaping (QuantityPreference, QuantityPreference?) -> Void = { _, _ in }) {
        let snapshot = entry?.foodConfigurationSnapshot ?? component?.foodConfigurationSnapshot ?? initialConfiguration?.snapshot
        let isHistorical = entry != nil || (component != nil && !isNewComponent)
        let historicalBase = snapshot?.baseFood ?? (isHistorical ? food : catalog.food(sourceID: food.sourceID, source: food.source) ?? food)
        let needsLegacyRebuild = isHistorical && (snapshot != nil || historicalBase.source == .chaseFood) && snapshot?.hasEditorInputs != true
        let currentCatalogFood = needsLegacyRebuild ? catalog.food(sourceID: historicalBase.sourceID, source: historicalBase.source) : nil
        let base = currentCatalogFood ?? historicalBase
        _food = State(initialValue: base)
        _notes = State(initialValue: component?.notes)
        self.catalog = catalog
        self.date = date
        self.initialConfiguration = initialConfiguration
        _selectedVariationID = State(initialValue: initialConfiguration?.id)
        _originalEntry = State(initialValue: entry)
        self.originalComponent = component
        componentActionTitle = isNewComponent ? "Add to parent" : "Use changes"
        self.onComponentSaved = onComponentSaved
        self.onLogged = onLogged
        let loadedOptions = needsLegacyRebuild
            ? (base.source == .chaseFood ? catalog.chaseFoodOptions(for: base.sourceID) : [])
            : snapshot?.options ?? (base.source == .chaseFood ? catalog.chaseFoodOptions(for: base.sourceID) : [])
        let initialSelectedOptionIDs = Set(initialConfiguration?.selectedOptionIDs
            ?? snapshot?.selectedOptionIDs
            ?? loadedOptions.filter(\.includedByDefault).map(\.id))
        let compatibleConfiguration = FoodConfigurationCompatibility.removingLegacyBurgerFries(
            baseFoodID: initialConfiguration?.baseFoodID ?? base.sourceID,
            options: loadedOptions,
            selectedOptionIDs: initialSelectedOptionIDs
        )
        let options = compatibleConfiguration.options
        _optionDefinitions = State(initialValue: options)
        _removedLegacyBurgerFries = State(initialValue: compatibleConfiguration.removedFries)
        _preservesLegacySnapshot = State(initialValue: needsLegacyRebuild && currentCatalogFood == nil)
        _rebuiltLegacyValues = State(initialValue: needsLegacyRebuild && currentCatalogFood.map { $0 != historicalBase } == true)
        _selectedOptionIDs = State(initialValue: needsLegacyRebuild
            ? Set(options.filter(\.includedByDefault).map(\.id))
            : compatibleConfiguration.selectedOptionIDs)
        _extraComponents = State(initialValue: needsLegacyRebuild ? [] : initialConfiguration?.components ?? snapshot?.extraComponents ?? snapshot?.components ?? [])
        let initialPortionID: String
        if let entry {
            let historicalPortionID = entry.portionID ?? ""
            initialPortionID = base.portion(id: historicalPortionID) != nil ? historicalPortionID : base.availablePortions.first?.id ?? historicalPortionID
        }
        else if let configuration = initialConfiguration { initialPortionID = configuration.portionID ?? "" }
        else if let component { initialPortionID = component.portionID ?? "" }
        else { initialPortionID = initialConfiguration?.portionID ?? base.availablePortions.first?.id ?? "" }
        _portionID = State(initialValue: initialPortionID)
        _initialQuantityPreference = State(initialValue: entry == nil && component == nil
            ? QuantityPreference(amount: 1, unit: .serving, portionID: initialPortionID.isEmpty ? nil : initialPortionID) : nil)
        let unit = entry?.unit ?? component?.unit ?? .serving
        _unitChoice = State(initialValue: unit == .grams ? .grams : unit == .ounces ? .ounces : .portion(initialPortionID))
        _amount = State(initialValue: entry?.amount ?? component?.amount ?? 1)
        _processedMeatOverride = State(initialValue: entry?.processedMeatOverride ?? component?.processedMeatOverride)
        _redMeatOverride = State(initialValue: entry?.redMeatOverride ?? component?.redMeatOverride)
    }

    private var options: [ChaseFoodOption] { optionDefinitions }
    private var companionRecommendations: [ChaseFoodCompanion] {
        catalog.chaseFoodCompanions(for: food)
    }
    private var selectedCompanionFoods: [Food] {
        companionRecommendations.filter { selectedCompanionFoodIDs.contains($0.id) }.map(\.food)
    }
    private var recentConfigurations: [SavedFoodConfiguration] {
        diary.document.savedFoodConfigurations
            .filter { $0.baseFoodID == food.id }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .prefix(5)
            .map { $0 }
    }
    private var optionGroups: [ChaseFoodOptionGroup] {
        var grouped: [String: [ChaseFoodOption]] = [:]
        for option in options {
            if let name = option.optionGroup {
                grouped[name, default: []].append(option)
            }
        }
        return grouped.map { key, values in
            ChaseFoodOptionGroup(
                name: key,
                selectionMode: values.first?.selectionMode ?? "multiple",
                options: values.sorted { $0.displayOrder < $1.displayOrder }
            )
        }
        .sorted { ($0.options.first?.displayOrder ?? 0) < ($1.options.first?.displayOrder ?? 0) }
    }
    private var includedOptions: [ChaseFoodOption] { options.filter { $0.optionGroup == nil && $0.includedByDefault } }
    private var additionOptions: [ChaseFoodOption] { options.filter { $0.optionGroup == nil && !$0.includedByDefault } }
    private var selectedPortionID: String? { portionID.isEmpty ? nil : portionID }
    private var selectedPortionGrams: Double {
        food.portion(id: selectedPortionID)?.grams ?? food.baseAmountGrams
    }
    private var quantityInSelectedPortions: Double {
        switch unitChoice {
        case .portion:
            max(amount, 0)
        case .grams:
            max(amount, 0) / max(selectedPortionGrams, 0.001)
        case .ounces:
            max(amount, 0) * 28.349_523_125 / max(selectedPortionGrams, 0.001)
        }
    }
    private var selectedUnit: LogUnit {
        switch unitChoice {
        case .portion: .serving
        case .grams: .grams
        case .ounces: .ounces
        }
    }
    private var totalNutrients: MacroNutrients {
        if (preservesLegacySnapshot || (options.isEmpty && extraComponents.isEmpty && originalEntry?.foodConfigurationSnapshot == nil && food == originalEntry?.food)), let entry = originalEntry {
            let oldGrams = entry.unit.grams(for: entry.amount, food: entry.food, portionID: entry.portionID)
            return entry.nutrients.scaled(by: currentQuantityInGrams / max(oldGrams, 0.001))
        }
        return configuredPortionNutrients.scaled(by: quantityInSelectedPortions)
    }
    private var configuredPortionNutrients: MacroNutrients {
        if preservesLegacySnapshot { return food.nutrients(for: 1, unit: .serving, portionID: selectedPortionID) }
        return FoodConfigurationCalculator.nutrients(food: food, options: options, selected: selectedOptionIDs,
            extras: extraComponents, portionID: selectedPortionID)
    }

    var body: some View {
        NavigationStack {
            CustomizationScreen(title: food.name, subtitle: food.displayBrand ?? "",
                nutrients: totalNutrients, actionTitle: originalEntry != nil ? "Save changes" : onComponentSaved != nil ? componentActionTitle : "Log Food",
                actionID: "food-detail-save", canSave: amount.isFinite && amount > 0 && !isCommitting && !diary.isSaving,
                action: logConfiguration, menu: { itemMenu }, quantity: { quantityControls }) {
                    VStack(alignment: .leading, spacing: 26) {
                        if rebuiltLegacyValues {
                            Text("Rebuilt with current catalog values. Save to update this item.")
                                .font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.muted)
                        }
                        if !includedOptions.isEmpty || !additionOptions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("Add to this food or meal")
                                Text("Tap any option; totals update instantly.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.muted)
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(includedOptions) { option in
                                        optionPill(option, defaultSelected: true)
                                    }
                                    ForEach(additionOptions) { option in
                                        optionPill(option, defaultSelected: false)
                                    }
                                }
                            }
                        }

                        ForEach(optionGroups) { group in
                            optionSection(group.name, options: group.options)
                        }

                        if originalEntry == nil, originalComponent == nil, onComponentSaved == nil,
                           !companionRecommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("Add as separate foods")
                                Text("Each selected food is logged on its own with its usual portion.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.muted)
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                    ForEach(companionRecommendations) { companion in
                                        companionPill(companion)
                                    }
                                }
                            }
                        }

                        if removedLegacyBurgerFries {
                            Text("Fries from this saved variation are now listed as a separate food above.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.muted)
                        }

                        if food.source == .chaseFood || !extraComponents.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                if food.source == .chaseFood {
                                    sectionLabel("Add another ingredient")
                                    Button {
                                        showingIngredientSearch = true
                                    } label: {
                                        Label("Add another food", systemImage: "plus")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(AppTheme.coral)
                                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                            .padding(.horizontal, 16)
                                            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.controlFill, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("custom-food-add-ingredient")
                                    .disabled(preservesLegacySnapshot)
                                }
                                if !extraComponents.isEmpty {
                                    CustomizationIngredients(items: $extraComponents, onEdit: { editingComponent = $0 })
                                        .disabled(preservesLegacySnapshot)
                                }
                            }
                        }

                        if let notes { Text(notes).font(.subheadline).foregroundStyle(AppTheme.muted) }
                        if food.availablePortions.contains(where: { $0.id == "imported-serving" }) {
                            Button("Edit ingredient definition") { showingDefinitionEditor = true }
                        }
                        if originalEntry == nil && onComponentSaved == nil {
                            VStack(alignment: .leading, spacing: 10) {
                                NavigationLink {
                                    SuggestedChangesEditor(text: $suggestedChanges)
                                } label: {
                                    Text("Suggest a change")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.coral)
                                        .underline()
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("custom-food-show-suggestions")
                                if selectedVariationID != nil {
                                    Button("Delete this variation", role: .destructive) {
                                        confirmingVariationDeletion = true
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .underline()
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                                    .accessibilityIdentifier("custom-food-delete-variation")
                                }
                            }
                        }
                    }
            }
            .onAppear {
                guard originalEntry == nil, originalComponent == nil, initialConfiguration == nil, food.source != .chaseFood, !didLoadPreference else { return }
                didLoadPreference = true
                let preference = diary.preference(for: food)
                initialQuantityPreference = preference
                amount = preference.amount; portionID = preference.portionID ?? ""
                unitChoice = preference.unit == .grams ? .grams : preference.unit == .ounces ? .ounces : .portion(portionID)
            }
            .sheet(isPresented: $showingDefinitionEditor) {
                ImportedDefinitionEditor(item: draft) { item in food = item.food; notes = item.notes }
            }
            .sheet(isPresented: $showingIngredientSearch) { ingredientSearchSheet }
            .sheet(isPresented: $showingNameEditor) {
                CustomizationNameEditor(name: food.name, title: "Edit food name") { name in
                    diary.run {
                        guard try await diary.renameFood(foodID: food.id, name: name) else { return }
                        food.name = name
                        if let entryID = originalEntry?.id { originalEntry = diary.document.entries.first { $0.id == entryID } }
                    }
                }
            }
            .sheet(item: $editingComponent) { item in
                MealComponentQuantityEditor(item: item) { updated in
                    if let index = extraComponents.firstIndex(where: { $0.id == item.id }) { extraComponents[index] = updated }
                    editingComponent = nil
                }
            }
            .confirmationDialog("Delete this saved variation?", isPresented: $confirmingVariationDeletion, titleVisibility: .visible) {
                Button("Delete variation", role: .destructive) {
                    guard let selectedVariationID else { return }
                    diary.run {
                        try await diary.deleteSavedFoodConfiguration(id: selectedVariationID)
                        self.selectedVariationID = nil
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the variation from Recent Variations. It does not change foods already logged.")
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var ingredientSearchSheet: some View {
        FoodPickerView(date: date, catalog: catalog, componentSelection: ComponentSelectionContext(
            excludedFoodIDs: [food.id], excludedMealIDs: [], onSelect: { extraComponents += $0 }))
    }

    private struct SuggestedChangesEditor: View {
        @Environment(\.dismiss) private var dismiss
        @Binding var text: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("custom-food-suggested-changes")
                Text("This feedback is saved with your diary data and sent to your analytics server.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Suggested changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var itemMenu: some View {
        if onComponentSaved == nil {
            Button(diary.isFavorite(food) ? "Unfavorite" : "Favorite", systemImage: diary.isFavorite(food) ? "star.fill" : "star") {
                diary.run { try await diary.toggleFavorite(food, preference: QuantityPreference(amount: amount, unit: selectedUnit, portionID: selectedPortionID)) }
            }
        }
        if onComponentSaved == nil {
            Button("Rename") { showingNameEditor = true }
        }
        Divider()
        Section("Recent Variations") {
            if recentConfigurations.isEmpty {
                Text("No saved variations yet")
            } else {
                ForEach(recentConfigurations) { configuration in
                    Button(displayLabel(configuration)) {
                        apply(configuration)
                        selectedVariationID = configuration.id
                    }.disabled(preservesLegacySnapshot)
                }
            }
        }
    }
    private var quantityControls: some View {
        CustomizationQuantityControls(amount: $amount, identifier: "custom-food-quantity-value") { unitControl }
    }
    private var unitControl: some View {
        Menu {
            Picker("Unit", selection: unitSelection) {
                ForEach(availableChoices, id: \.self) { choice in
                    Text(label(for: choice)).tag(choice)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label(for: unitChoice))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.coral)
            .padding(.horizontal, 9)
            .frame(minWidth: 76, minHeight: 40, maxHeight: 40)
            .background(AppTheme.coral.opacity(0.10), in: Capsule())
        }
        .frame(maxWidth: 210)
        .layoutPriority(1)
        .accessibilityLabel("Portion or unit")
        .accessibilityValue(label(for: unitChoice))
        .accessibilityIdentifier("custom-food-unit-picker")
    }

    private var availableChoices: [QuantityUnitChoice] {
        food.availablePortions.map { .portion($0.id) } + [.ounces, .grams] + (unitChoice == .portion("") ? [.portion("")] : [])
    }

    private var unitSelection: Binding<QuantityUnitChoice> {
        Binding(get: { unitChoice }, set: { choice in
            let grams = currentQuantityInGrams
            let previousUnit = selectedUnit
            let previousPortion = selectedPortionID
            switch choice {
            case .portion(let id):
                portionID = id
                amount = grams / max(food.portion(id: id)?.grams ?? food.baseAmountGrams, 0.001)
            case .grams: amount = grams
            case .ounces: amount = grams / 28.349_523_125
            }
            unitChoice = choice
            AppAnalytics.capture(onComponentSaved == nil ? "food_log.unit_selected" : "food_component.unit_selected",
                properties: FoodLogAnalytics.unitSelectionProperties(food: food, operation: originalEntry == nil ? "create" : "edit",
                    fromUnit: previousUnit, fromPortionID: previousPortion, selectedUnit: selectedUnit,
                    selectedPortionID: selectedPortionID, defaultUnit: initialQuantityPreference?.unit ?? previousUnit,
                    defaultPortionID: initialQuantityPreference?.portionID ?? previousPortion))
        })
    }

    private var currentQuantityInGrams: Double {
        switch unitChoice {
        case .portion: amount * selectedPortionGrams
        case .grams: amount
        case .ounces: amount * 28.349_523_125
        }
    }

    private func label(for choice: QuantityUnitChoice) -> String {
        return switch choice {
        case .ounces: "ounces"
        case .grams: "grams"
        case .portion(let id):
            if let portion = food.portion(id: id) { portionDisplayLabel(portion) }
            else { "serving" }
        }
    }

    private func portionDisplayLabel(_ portion: FoodPortion) -> String {
        var label = portion.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if suffix.caseInsensitiveCompare("Taco") == .orderedSame,
           let qualifier = label.range(of: " (", options: .backwards) {
            label = String(label[..<qualifier.lowerBound])
        }
        guard !suffix.isEmpty,
              label.lowercased().hasSuffix(" " + suffix.lowercased()) else { return label }
        return String(label.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.muted)
    }

    private func optionSection(_ title: String, options: [ChaseFoodOption]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(title)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(options) { option in optionPill(option, defaultSelected: option.includedByDefault) }
            }
        }
    }

    private func optionPill(_ option: ChaseFoodOption, defaultSelected: Bool) -> some View {
        let selected = selectedOptionIDs.contains(option.id)
        let calories = Int(option.food.nutrients(for: option.amountGrams, unit: .grams).calories.rounded())
        return selectionPill(
            title: option.displayName,
            detail: defaultSelected ? "\(calories) kcal" : "+\(calories) kcal",
            isSelected: selected
        ) { setOption(option, selected: !selected) }
        .disabled(preservesLegacySnapshot)
    }

    private func companionPill(_ companion: ChaseFoodCompanion) -> some View {
        let selected = selectedCompanionFoodIDs.contains(companion.id)
        let preference = diary.preference(for: companion.food)
        let calories = Int(companion.food.nutrients(
            for: preference.amount,
            unit: preference.unit,
            portionID: preference.portionID
        ).calories.rounded())
        let amount = preference.amount.formatted(.number.precision(.fractionLength(0...2)))
        return selectionPill(
            title: companion.displayName,
            detail: "\(calories) kcal · \(amount) \(preference.unit.title)",
            isSelected: selected
        ) {
            if selected { selectedCompanionFoodIDs.remove(companion.id) }
            else { selectedCompanionFoodIDs.insert(companion.id) }
        }
        .accessibilityIdentifier("food-companion-\(companion.id)")
    }

    private func selectionPill(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .fill(isSelected ? AppTheme.coral : AppTheme.muted.opacity(0.45))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(isSelected ? AppTheme.coral : AppTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.coral)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(isSelected ? AppTheme.coral.opacity(0.13) : AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? AppTheme.coral : AppTheme.controlFill, lineWidth: 1.25))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ink)
        .accessibilityLabel(title)
        .accessibilityValue("\(isSelected ? "Selected" : "Not selected"), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func setOption(_ option: ChaseFoodOption, selected: Bool) {
        guard let group = option.optionGroup,
              let definition = optionGroups.first(where: { $0.name == group }),
              definition.selectionMode == "exclusive" else {
            if selected { selectedOptionIDs.insert(option.id) } else { selectedOptionIDs.remove(option.id) }
            return
        }
        for candidate in definition.options { selectedOptionIDs.remove(candidate.id) }
        if selected { selectedOptionIDs.insert(option.id) }
    }

    private func exclusiveSelection(for group: ChaseFoodOptionGroup) -> Binding<String> {
        Binding(
            get: { group.options.first(where: { selectedOptionIDs.contains($0.id) })?.id ?? "" },
            set: { selection in
                for option in group.options { selectedOptionIDs.remove(option.id) }
                if !selection.isEmpty { selectedOptionIDs.insert(selection) }
            }
        )
    }

    private var configuredComponents: [MealItem] {
        let hasVariant = options.contains {
            $0.relationship.caseInsensitiveCompare("variant") == .orderedSame
                && selectedOptionIDs.contains($0.id)
        }
        var selected = options.filter {
            selectedOptionIDs.contains($0.id) && $0.food.id != food.id
                && $0.relationship.caseInsensitiveCompare("style") != .orderedSame
                && (!hasVariant || !$0.includedByDefault || $0.relationship.caseInsensitiveCompare("variant") == .orderedSame)
        }.map { option in
            let amount = option.relationship.caseInsensitiveCompare("variant") == .orderedSame
                ? (food.portion(id: selectedPortionID)?.grams ?? food.baseAmountGrams)
                : option.amountGrams
            return MealItem(id: UUID(), food: option.food, amount: amount, unit: .grams, configurationOptionID: option.id)
        }
        selected += extraComponents
        return selected
    }

    private var variationLabel: String {
        let hasVariant = options.contains {
            $0.relationship.caseInsensitiveCompare("variant") == .orderedSame
                && selectedOptionIDs.contains($0.id)
        }
        let details = options.filter {
            selectedOptionIDs.contains($0.id) && $0.food.id != food.id
                && $0.relationship.caseInsensitiveCompare("style") != .orderedSame
        }.map(\.displayName)
            + extraComponents.map(\.food.name)
            + (hasVariant ? [] : includedOptions.filter { !selectedOptionIDs.contains($0.id) }.map { "no \($0.food.name.lowercased())" })
        let style = options.first {
            $0.optionGroup == "Style" && selectedOptionIDs.contains($0.id) && !$0.includedByDefault
        }?.displayName
        let namedDetails = details + (style.map { [$0] } ?? [])
        let portion = food.portion(id: selectedPortionID).map(portionDisplayLabel) ?? "serving"
        let normalizedPortion = portion.replacingOccurrences(of: " · ", with: ", ")
        return ([normalizedPortion] + namedDetails).joined(separator: ", ")
    }

    private func displayLabel(_ configuration: SavedFoodConfiguration) -> String {
        var label = configuration.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let foodName = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" · ", " • ", ", "] {
            let prefix = foodName + separator
            if label.range(of: prefix, options: .caseInsensitive).map({ $0.lowerBound == label.startIndex }) == true {
                label = String(label.dropFirst(prefix.count))
                break
            }
        }
        return label.replacingOccurrences(of: " · ", with: ", ")
            .replacingOccurrences(of: " • ", with: ", ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
    }

    private func apply(_ configuration: SavedFoodConfiguration) {
        let loadedOptions = configuration.snapshot?.options
            ?? (food.source == .chaseFood ? catalog.chaseFoodOptions(for: food.sourceID) : [])
        let compatibleConfiguration = FoodConfigurationCompatibility.removingLegacyBurgerFries(
            baseFoodID: configuration.baseFoodID,
            options: loadedOptions,
            selectedOptionIDs: Set(configuration.selectedOptionIDs)
        )
        optionDefinitions = compatibleConfiguration.options
        selectedOptionIDs = compatibleConfiguration.selectedOptionIDs
        removedLegacyBurgerFries = compatibleConfiguration.removedFries
        extraComponents = configuration.components
        if let base = configuration.snapshot?.baseFood { food = base }
        if let portionID = configuration.portionID, food.portion(id: portionID) != nil {
            self.portionID = portionID
            unitChoice = .portion(portionID)
            amount = 1
        }
        selectedVariationID = configuration.id
    }

    private var draft: MealItem {
        var result = originalComponent ?? originalEntry?.foodDraft ?? MealItem(id: UUID(), food: food, amount: amount, unit: selectedUnit)
        // Unchanged inputs keep exact historical totals, snapshots and component IDs.
        let previous = originalEntry?.foodConfigurationSnapshot ?? originalComponent?.foodConfigurationSnapshot
        let unchanged = previous?.baseFood == food && Set(previous?.selectedOptionIDs ?? []) == selectedOptionIDs
            && previous?.extraComponents == extraComponents && previous?.portionID == selectedPortionID
        if options.isEmpty && extraComponents.isEmpty && previous == nil {
            result.food = food
        } else if !preservesLegacySnapshot && !unchanged {
            result.food = FoodConfigurationCalculator.configuredFood(base: food, portionNutrients: configuredPortionNutrients, portionID: selectedPortionID)
            result.foodConfigurationSnapshot = FoodConfigurationSnapshot(selectedOptionIDs: Array(selectedOptionIDs).sorted(),
                components: configuredComponents, suggestedChanges: suggestedChanges.isEmpty ? nil : suggestedChanges,
                catalogVersion: catalog.catalogVersion, baseFood: food, options: options,
                extraComponents: extraComponents, portionID: selectedPortionID)
        }
        result.notes = notes
        result.amount = amount
        result.unit = selectedUnit
        result.portionID = selectedPortionID
        result.processedMeatOverride = processedMeatOverride
        result.redMeatOverride = redMeatOverride
        return result
    }

    private func logConfiguration() {
        guard amount.isFinite, amount > 0, !isCommitting, !diary.isSaving else { return }
        let result = draft
        if let onComponentSaved { onComponentSaved(result); dismiss(); return }
        isCommitting = true
        diary.run(operation: "chase_food_configured_commit") {
            defer { isCommitting = false }
            if let originalEntry {
                try await diary.updateFoodDraft(draft: result, original: originalEntry)
            } else if options.isEmpty && extraComponents.isEmpty && result.foodConfigurationSnapshot == nil {
                if selectedCompanionFoods.isEmpty {
                    try await diary.log(food, amount: amount, unit: selectedUnit, portionID: selectedPortionID, on: date, allowCheatDay: true)
                } else {
                    try await diary.logFoodWithCompanions(food, amount: amount, unit: selectedUnit,
                        portionID: selectedPortionID, companions: selectedCompanionFoods, on: date)
                }
                onLogged(QuantityPreference(amount: amount, unit: selectedUnit, portionID: selectedPortionID), initialQuantityPreference)
            } else {
                let note = suggestedChanges.trimmingCharacters(in: .whitespacesAndNewlines)
                let suggestion = note.isEmpty ? nil : FoodSuggestion(kind: .changeToFood, suggestedName: food.name, suggestedChanges: note, foodID: food.id)
                var configuration = SavedFoodConfiguration(baseFoodID: food.id, label: variationLabel,
                    selectedOptionIDs: Array(selectedOptionIDs).sorted(), components: extraComponents, portionID: selectedPortionID)
                configuration.snapshot = result.foodConfigurationSnapshot
                try await diary.logConfiguredFood(food, nutrients: totalNutrients, selectedOptionIDs: configuration.selectedOptionIDs,
                    components: configuredComponents, suggestedChanges: note.isEmpty ? nil : note,
                    portionID: selectedPortionID, amount: amount, unit: selectedUnit,
                    snapshot: result.foodConfigurationSnapshot, companions: selectedCompanionFoods,
                    configuration: configuration, suggestion: suggestion,
                    on: date, allowCheatDay: true)
                onLogged(QuantityPreference(amount: amount, unit: selectedUnit, portionID: selectedPortionID), initialQuantityPreference)
                AppAnalytics.capture("food.logged", properties: ["source": food.source.rawValue, "method": "customize"])
            }
            diary.rememberLastWeightUnit(selectedUnit)
            dismiss()
        }
    }
}

/// Search, diary, variations and parent drafts all resolve food capabilities here.
struct FoodDetailView: View {
    enum Context {
        case log(Food, Date, SavedFoodConfiguration?, (QuantityPreference, QuantityPreference?) -> Void)
        case logged(DiaryEntry)
        case component(MealItem, Date, SavedFoodConfiguration?, Bool, (MealItem) -> Void)
    }
    let context: Context
    let catalog: CatalogStore

    init(food: Food, catalog: CatalogStore, date: Date, initialConfiguration: SavedFoodConfiguration? = nil,
         onLogged: @escaping (QuantityPreference, QuantityPreference?) -> Void = { _, _ in }) {
        self.context = .log(food, date, initialConfiguration, onLogged)
        self.catalog = catalog
    }
    init(entry: DiaryEntry, catalog: CatalogStore) { context = .logged(entry); self.catalog = catalog }
    init(item: MealItem, catalog: CatalogStore, date: Date, initialConfiguration: SavedFoodConfiguration? = nil, isNewSelection: Bool = false,
         onSave: @escaping (MealItem) -> Void) {
        context = .component(item, date, initialConfiguration, isNewSelection, onSave)
        self.catalog = catalog
    }

    var body: some View {
        Group {
            switch context {
            case let .log(food, date, configuration, onLogged):
                FoodCustomizationView(food: food, catalog: catalog, date: date,
                    initialConfiguration: configuration, onLogged: onLogged)
            case .logged(let entry):
                FoodCustomizationView(food: entry.food, catalog: catalog, date: entry.date, entry: entry)
            case let .component(item, date, configuration, isNew, onSave):
                FoodCustomizationView(food: item.food, catalog: catalog, date: date,
                    initialConfiguration: configuration, component: item, isNewComponent: isNew, onComponentSaved: onSave)
            }
        }
        .draftSaveError()
    }
}

struct LoggedItemDetailView: View {
    @EnvironmentObject private var diary: DiaryStore
    let entryID: UUID
    let catalog: CatalogStore
    @State private var presentedEntry: DiaryEntry?
    @State private var didResolve = false
    var body: some View {
        Group {
            if let entry = presentedEntry {
                if entry.foodConfigurationSnapshot != nil || !entry.isMeal {
                    FoodDetailView(entry: entry, catalog: catalog)
                } else { MealDetailView(context: .logged(entry), catalog: catalog) }
            } else if didResolve {
                ContentUnavailableView("Item no longer available", systemImage: "fork.knife")
            } else { ProgressView("Opening logged item…") }
        }
        .task {
            guard !didResolve else { return }
            // Resolve once at presentation. Later store refreshes must not replace the
            // original revision while a user still has an unsaved value draft.
            presentedEntry = diary.document.entries.first { $0.id == entryID }
            didResolve = true
        }
    }
}

struct ComponentSelectionContext {
    var excludedFoodIDs: Set<String> = []
    var excludedMealIDs: Set<UUID> = []
    let onSelect: ([MealItem]) -> Void
}

private struct DraftSaveErrorModifier: ViewModifier {
    @EnvironmentObject private var diary: DiaryStore
    func body(content: Content) -> some View {
        content.alert("Changes were not saved", isPresented: Binding(
            get: { diary.lastSaveError != nil }, set: { if !$0 { diary.dismissSaveError() } })) {
                Button("OK", role: .cancel) { diary.dismissSaveError() }
            } message: { Text(diary.lastSaveError ?? "Try saving again.") }
    }
}

extension View {
    func draftSaveError() -> some View { modifier(DraftSaveErrorModifier()) }
}

enum QuantityUnitChoice: Hashable {
    case ounces
    case grams
    case portion(String)
}

struct CustomizationNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let title: String
    let onSave: (String) -> Void

    init(name: String, title: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: name)
        self.title = title
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name).textInputAutocapitalization(.words)
                    .accessibilityIdentifier("customization-name-field")
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("customization-name-save")
                }
            }
        }
        .presentationDetents([.height(230)])
    }
}


/// The same pinned summary, scrolling content and quantity/action footer for every source.
struct CustomizationScreen<Content: View, Quantity: View, MenuContent: View>: View {
    let title: String
    let subtitle: String
    var headerIcon: String? = nil
    let nutrients: MacroNutrients
    let actionTitle: String
    let actionID: String
    let canSave: Bool
    let action: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @ViewBuilder var quantity: () -> Quantity
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            CustomizationSummary(title: title, subtitle: subtitle, headerIcon: headerIcon,
                totalNutrients: nutrients, menu: menu())
            ScrollView {
                content().padding(.horizontal, 20).padding(.vertical, 20)
                    .frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden).accessibilityIdentifier("customization-content")
            footer
        }
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.coral)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
    }
    private var footer: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                Text("PORTION & QUANTITY").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.muted)
                quantity()
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(AppTheme.controlFill, lineWidth: 1))
            Button(action: action) {
                Text(actionTitle).font(.headline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 58)
                    .background(AppTheme.coral, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1 : 0.5)
                .accessibilityIdentifier(actionID).shadow(color: AppTheme.coral.opacity(0.24), radius: 10, y: 5)
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            .background { Rectangle().fill(.ultraThinMaterial).overlay(AppTheme.background.opacity(0.72)).ignoresSafeArea(edges: .bottom) }
    }
}

private struct CustomizationSummary<MenuContent: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let headerIcon: String?
    let totalNutrients: MacroNutrients
    let menu: MenuContent
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.coral)
                        .frame(width: 36, height: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("custom-food-back")
                if let headerIcon {
                    Image(systemName: headerIcon)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(AppTheme.coral)
                        .accessibilityLabel("Meal")
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .accessibilityIdentifier("custom-food-sticky-title")
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(AppTheme.muted)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu { menu } label: {
                    Image(systemName: "line.3.horizontal").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.muted).frame(width: 36, height: 36)
                }.accessibilityLabel("Item actions").accessibilityIdentifier("custom-food-recent-variations")
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                calorieValue
                macroValue("Carbs", value: totalNutrients.carbs, color: AppTheme.carbs)
                Spacer(minLength: 0)
                macroValue("Fat", value: totalNutrients.fat, color: AppTheme.fat)
                Spacer(minLength: 0)
                macroValue("Protein", value: totalNutrients.protein, color: AppTheme.protein)
            }
            macroBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
        .overlay(alignment: .bottom) { AppTheme.controlFill.frame(height: 1) }
    }

    private var calorieValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(Int(totalNutrients.calories.rounded()))")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
            Text("kcal")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories \(Int(totalNutrients.calories.rounded())) kcal")
        .accessibilityIdentifier("custom-food-estimate-calories")
    }

    private var macroBar: some View {
        let carbs = max(totalNutrients.carbs, 0)
        let fat = max(totalNutrients.fat, 0)
        let protein = max(totalNutrients.protein, 0)
        let total = carbs + fat + protein
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                if total > 0 {
                    Rectangle().fill(AppTheme.carbs).frame(width: geometry.size.width * CGFloat(carbs / total))
                    Rectangle().fill(AppTheme.fat).frame(width: geometry.size.width * CGFloat(fat / total))
                    Rectangle().fill(AppTheme.protein).frame(width: geometry.size.width * CGFloat(protein / total))
                } else {
                    Rectangle().fill(AppTheme.controlFill)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carbs \(carbs.cleanAmount) grams, fat \(fat.cleanAmount) grams, protein \(protein.cleanAmount) grams")
        .accessibilityIdentifier("custom-food-macro-bar")
    }

    private func macroValue(_ title: String, value: Double, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).foregroundStyle(AppTheme.muted)
            Text("\(value.cleanAmount) g").foregroundStyle(color)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

}


/// Food extras and meal ingredients share editing, removal and ordering affordances.
struct CustomizationIngredients: View {
    @State private var revealedItemID: UUID?
    @State private var pendingRemoval: MealItem?
    @State private var confirmingRemoval = false
    @Binding var items: [MealItem]
    let onEdit: (MealItem) -> Void
    var body: some View {
        VStack(spacing: 12) {
            ForEach($items) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        MealItemRow(item: item.wrappedValue)
                        Button("Customize", systemImage: "slider.horizontal.3") { onEdit(item.wrappedValue) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.coral)
                            .accessibilityLabel("Customize " + item.wrappedValue.food.name)
                            .accessibilityIdentifier("meal-component-edit-" + item.wrappedValue.food.sourceID)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.controlFill, lineWidth: 1))
                    if revealedItemID == item.wrappedValue.id {
                        Button {
                            pendingRemoval = item.wrappedValue
                            confirmingRemoval = true
                        } label: {
                            Image(systemName: "trash.fill").font(.headline).foregroundStyle(.white)
                                .frame(width: 54, height: 86)
                                .background(AppTheme.coral, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel("Delete " + item.wrappedValue.food.name)
                        .accessibilityIdentifier("meal-component-delete-" + item.wrappedValue.food.sourceID)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 22).onEnded { value in
                    if value.translation.width < -45 {
                        withAnimation(.easeOut(duration: 0.18)) { revealedItemID = item.wrappedValue.id }
                    } else if value.translation.width > 45 {
                        withAnimation(.easeOut(duration: 0.18)) { revealedItemID = nil }
                    }
                })
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("meal-component-row-" + item.wrappedValue.food.sourceID)
            }
        }
        .confirmationDialog("Remove this food?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                guard let pendingRemoval else { return }
                items.removeAll { $0.id == pendingRemoval.id }
                revealedItemID = nil
                self.pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let pendingRemoval { Text("Remove \(pendingRemoval.food.name) from this item?") }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Deterministic review routes use the production views and catalog, never a drawn mockup or AI request.
struct CustomizationEvidenceView: View {
    let route: String
    let catalog: CatalogStore
    private let date = Calendar.current.startOfDay(for: Date())
    private var plum: Food { catalog.food(sourceID: "2709265", source: .usda)! }
    private var rice: Food { catalog.food(sourceID: "2708422", source: .usda)! }
    private var packaged: Food { catalog.food(sourceID: "0096619483556", source: .openFoodFacts)! }
    private var sandwich: Food { catalog.food(sourceID: "food_sandwich", source: .chaseFood)! }
    private var definition: CustomFoodDefinition {
        CustomFoodDefinition(name: "Chase's overnight oats", servingDescription: "jar", servingGrams: 250,
            nutrition: .init(calories: 320, carbohydratesGrams: 48, fatGrams: 9, proteinGrams: 14, fiberGrams: 8),
            notes: "Oats, milk and berries. Review the estimate before logging.", containsProcessedMeat: false, containsRedMeat: false)
    }
    private var custom: Food { definition.makeFood(sourceID: "task196-oats") }
    private var meal: SavedMeal {
        SavedMeal(id: UUID(uuidString: "19600000-0000-4000-8000-000000000001")!, name: "Yogurt, fruit and oats",
            items: [MealItem(id: UUID(), food: plum, amount: 1, unit: .serving, portionID: "306269"),
                MealItem(id: UUID(), food: packaged, amount: 1, unit: .serving, portionID: packaged.availablePortions.first?.id),
                MealItem(id: UUID(), food: custom, amount: 1, unit: .serving, portionID: "imported-serving")],
            notes: "A mixed-source meal: USDA fruit, packaged yogurt and a custom recipe.")
    }
    private var file: CustomMealFile {
        CustomMealFile(format: CustomMealFile.formatIdentifier, version: 1, name: "Reviewed breakfast bowl",
            foods: [definition,
                .init(name: "Greek yogurt", servingDescription: "cup", servingGrams: 170,
                    nutrition: .init(calories: 100, carbohydratesGrams: 7, fatGrams: 0, proteinGrams: 18), notes: "Plain nonfat yogurt."),
                .init(name: "Mixed berries", servingDescription: "handful", servingGrams: 80,
                    nutrition: .init(calories: 40, carbohydratesGrams: 10, fatGrams: 0.4, proteinGrams: 0.6, fiberGrams: 3), notes: nil)],
            notes: "Stored demo analysis. Review each ingredient and portion; no AI request is made.")
    }
    private var configuration: SavedFoodConfiguration {
        let options = catalog.chaseFoodOptions(for: sandwich.sourceID)
        let selected = options.filter(\.includedByDefault).map(\.id)
        let extras = [MealItem(id: UUID(), food: plum, amount: 1, unit: .serving, portionID: "306269")]
        var config = SavedFoodConfiguration(baseFoodID: sandwich.id, label: "Sandwich with plum", selectedOptionIDs: selected,
            components: extras, portionID: sandwich.availablePortions.first?.id)
        config.snapshot = FoodConfigurationSnapshot(selectedOptionIDs: selected, components: extras, suggestedChanges: nil,
            catalogVersion: catalog.catalogVersion, baseFood: sandwich, options: options, extraComponents: extras, portionID: config.portionID)
        return config
    }
    private func entry(_ food: Food, amount: Double = 1, unit: LogUnit = .serving, portion: String? = nil) -> DiaryEntry {
        DiaryEntry(id: UUID(), date: date, food: food, amount: amount, unit: unit,
            nutrients: food.nutrients(for: amount, unit: unit, portionID: portion), loggedAt: date, portionID: portion)
    }
    static func document(catalog: CatalogStore) -> DiaryDocument {
        let fixture = Self(route: "", catalog: catalog)
        var document = DiaryDocument()
        document.customFoods = [fixture.custom]
        document.meals = [fixture.meal]
        document.trackingStartDate = fixture.date
        var plum = fixture.entry(fixture.plum, portion: "306269")
        var packaged = fixture.entry(fixture.packaged, portion: fixture.packaged.availablePortions.first?.id)
        var configured = fixture.entry(fixture.sandwich, portion: fixture.configuration.portionID)
        configured.foodConfigurationSnapshot = fixture.configuration.snapshot
        configured.nutrients = FoodConfigurationCalculator.nutrients(food: fixture.sandwich,
            options: fixture.configuration.snapshot!.options!, selected: Set(fixture.configuration.selectedOptionIDs),
            extras: fixture.configuration.components, portionID: fixture.configuration.portionID)
        configured.food = FoodConfigurationCalculator.configuredFood(base: fixture.sandwich,
            portionNutrients: configured.nutrients, portionID: fixture.configuration.portionID)
        let meal = fixture.meal
        let mealFood = Food(sourceID: "task196-meal", source: .custom, name: meal.name, brand: nil, barcode: nil,
            nutrients: meal.nutrients, baseAmountGrams: 1, servingGrams: 1, servingDescription: "1 meal")
        var saved = fixture.entry(mealFood); saved.savedMealID = meal.id; saved.mealItems = meal.items; saved.mealNotes = meal.notes
        let oneOffFood = Food(sourceID: "task196-one-off", source: .custom, name: "One-off breakfast", brand: nil,
            barcode: nil, nutrients: meal.nutrients, baseAmountGrams: 1, servingGrams: 1, servingDescription: "1 meal")
        var oneOff = fixture.entry(oneOffFood)
        oneOff.mealItems = meal.items; oneOff.mealNotes = meal.notes
        plum.displayOrder = 0; packaged.displayOrder = 1; configured.displayOrder = 2; saved.displayOrder = 3; oneOff.displayOrder = 4
        document.entries = [plum, packaged, configured, saved, oneOff]
        return document
    }
    var body: some View {
        switch route {
        case "usda-portioned-log": FoodDetailView(food: plum, catalog: catalog, date: date)
        case "usda-weight-log": FoodDetailView(food: rice, catalog: catalog, date: date)
        case "off-packaged-log": FoodDetailView(food: packaged, catalog: catalog, date: date)
        case "yum-chase-configured-log": FoodDetailView(food: sandwich, catalog: catalog, date: date, initialConfiguration: configuration)
        case "custom-food-log": FoodDetailView(food: custom, catalog: catalog, date: date)
        case "saved-meal-log": MealDetailView(context: .log(meal, date, { _, _ in }), catalog: catalog)
        case "imported-meal-review": MealDetailView(context: .imported(file, date, .fileImport, nil), catalog: catalog)
        case "photo-meal-review": MealDetailView(context: .imported(file, date, .openAIAnalysis, nil), catalog: catalog)
        case "usda-portioned-edit": FoodDetailView(entry: entry(plum, portion: "306269"), catalog: catalog)
        case "off-packaged-edit": FoodDetailView(entry: entry(packaged, portion: packaged.availablePortions.first?.id), catalog: catalog)
        case "yum-chase-configured-edit":
            let config = configuration
            let base = sandwich
            let nutrients = FoodConfigurationCalculator.nutrients(food: base, options: config.snapshot!.options!,
                selected: Set(config.selectedOptionIDs), extras: config.components, portionID: config.portionID)
            var logged = entry(base, portion: config.portionID)
            let _ = { logged.food = FoodConfigurationCalculator.configuredFood(base: base, portionNutrients: nutrients, portionID: config.portionID)
                logged.nutrients = nutrients; logged.foodConfigurationSnapshot = config.snapshot }()
            FoodDetailView(entry: logged, catalog: catalog)
        default:
            let meal = meal
            var logged = entry(Food(sourceID: "task196-meal", source: .custom, name: meal.name, brand: nil, barcode: nil,
                nutrients: meal.nutrients, baseAmountGrams: 1, servingGrams: 1, servingDescription: "1 meal"))
            let _ = { logged.mealItems = meal.items; logged.mealNotes = meal.notes
                if route == "saved-meal-edit" { logged.savedMealID = meal.id } }()
            MealDetailView(context: .logged(logged), catalog: catalog)
        }
    }
}
#endif

struct CustomizationQuantityControls<UnitContent: View>: View {
    @Binding var amount: Double
    let identifier: String
    @ViewBuilder var unit: () -> UnitContent
    @FocusState private var isFocused: Bool
    var body: some View {
        HStack(spacing: 5) {
            adjuster("−1", delta: -1)
            TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).focused($isFocused).font(.subheadline.weight(.bold).monospacedDigit())
                .multilineTextAlignment(.center).frame(width: 48).padding(.horizontal, 4).padding(.vertical, 9)
                .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Quantity").accessibilityIdentifier(identifier)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.async { UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil) }
                    }
                }
            adjuster("+1", delta: 1)
            unit()
        }
    }
    private func adjuster(_ title: String, delta: Double) -> some View {
        Button {
            guard amount + delta > 0 else { return }
            amount += delta; isFocused = false
        } label: {
            Text(title).font(.caption.weight(.bold).monospacedDigit()).frame(width: 30, height: 36)
                .background(AppTheme.controlFill, in: Circle()).overlay(Circle().stroke(AppTheme.coral, lineWidth: 1.25))
        }.buttonStyle(.plain).foregroundStyle(AppTheme.coral).disabled(delta < 0 && amount <= 1)
            .opacity(delta < 0 && amount <= 1 ? 0.4 : 1)
            .accessibilityLabel(delta < 0 ? "Decrease quantity by one" : "Increase quantity by one")
            .accessibilityIdentifier(delta < 0 ? "custom-food-quantity-minus" : "custom-food-quantity-plus")
    }
}
