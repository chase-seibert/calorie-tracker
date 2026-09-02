import SwiftUI
import UIKit

/// Optional choices distinguish an untouched default from an intentional No.
struct FoodMeatFields: View {
    @EnvironmentObject private var diary: DiaryStore
    let name: String
    @Binding var processed: Bool?
    @Binding var red: Bool?
    var derivesFromIngredients = false
    var automaticProcessed: Bool? = nil
    var automaticRed: Bool? = nil
    @State private var suggestion: Food?

    var body: some View {
        Group {
            field("Contains processed meat", choice: $processed,
                  suggested: derivesFromIngredients ? automaticProcessed : suggestion?.containsProcessedMeat,
                  source: suggestion?.meatResolution?.processed)
            field("Contains red meat", choice: $red,
                  suggested: derivesFromIngredients ? automaticRed : suggestion?.containsRedMeat,
                  source: suggestion?.meatResolution?.red)
        }
        .task(id: name) {
            guard !derivesFromIngredients else { return }
            suggestion = nil
            let result = await diary.suggestedMeatClassification(name: name)
            guard !Task.isCancelled else { return }
            suggestion = result
        }
    }

    private func field(_ title: String, choice: Binding<Bool?>, suggested: Bool?, source: FoodMetadataSource?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: choice) {
                Text("Automatic").tag(nil as Bool?)
                Text("Yes").tag(true as Bool?)
                Text("No").tag(false as Bool?)
            }
            if let suggested {
                let reason = derivesFromIngredients ? "ingredients" : (source == .catalog ? "catalog match" : "food name")
                Text("Automatic: \(suggested ? "Yes" : "No") — \(reason)")
                    .font(.caption).foregroundStyle(.secondary)
                if let selected = choice.wrappedValue, selected != suggested {
                    Text("Your value differs from the suggestion. It will be kept unless you choose Automatic.")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else if choice.wrappedValue == nil {
                Text("Unknown — not counted as confirmed meat. Choose Yes or No if you know.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ReviewClassificationsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var reviews: [FoodResolutionReview] = []
    @State private var loading = true
    @State private var error: String?
    @State private var confirmingApprovals = false
    @State private var pendingApprovals: [FoodResolutionReview] = []

    var body: some View {
        List {
            Section {
                Text("Review missing or conflicting classifications in saved foods and diary history. Currently, suggestions cover processed and red meat. Corrections preserve nutrition, portions, and meal overrides.")
                if !reviews.isEmpty {
                    Button("Approve All (\(reviews.count))") {
                        pendingApprovals = reviews
                        confirmingApprovals = true
                    }
                    .disabled(loading || diary.isSaving || error != nil)
                    Text("Approve individually or approve all listed suggestions with one verified SQLite backup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if loading { ProgressView("Checking food snapshots…") }
            if diary.isSaving { ProgressView("Saving changes…") }
            if let error { Text(error).foregroundStyle(.red) }
            if !loading && error == nil && reviews.isEmpty { Text("No classification changes suggested.") }
            ForEach(reviews) { review in
                Section(review.food.name) {
                    Text("\(review.food.servingDescription ?? "Food snapshot") · \(review.food.nutrients.calories.cleanAmount) cal")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Processed meat: \(label(review.food.containsProcessedMeat)) → \(label(review.suggestion.containsProcessedMeat, suggestion: true))")
                    Text("Red meat: \(label(review.food.containsRedMeat)) → \(label(review.suggestion.containsRedMeat, suggestion: true))")
                    Text(review.suggestion.meatResolution?.processed == .catalog || review.suggestion.meatResolution?.red == .catalog
                         ? "Suggestion uses matching catalog foods." : "Suggestion uses the food name.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Only matching snapshots are updated. Existing explicit values require your approval here.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Approve Suggestion") { approve([review]) }
                        .disabled(loading || diary.isSaving || error != nil)
                }
            }
        }
        .navigationTitle("Review Classifications")
        .confirmationDialog("Approve all \(pendingApprovals.count) suggestions?", isPresented: $confirmingApprovals,
                            titleVisibility: .visible) {
            Button("Approve All") { approve(pendingApprovals) }
            Button("Cancel", role: .cancel) { pendingApprovals = [] }
        } message: {
            Text("This updates matching food snapshots throughout your history and library, including replacing existing explicit meat classifications. Nutrition, portions, and meal overrides stay unchanged. One verified SQLite backup is created first. If any suggestion is stale, none will be applied.")
        }
        .task { await reload() }
        .refreshable {
            guard !diary.isSaving && !confirmingApprovals else { return }
            await reload()
        }
    }

    private func label(_ value: Bool?, suggestion: Bool = false) -> String {
        value.map { $0 ? "Yes" : "No" } ?? (suggestion ? "Keep current (unknown)" : "Unknown")
    }

    private func approve(_ approvals: [FoodResolutionReview]) {
        diary.run {
            do { try await diary.applyFoodResolutionReviews(approvals) }
            catch {
                await reload()
                throw error
            }
            await reload()
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do { reviews = try await diary.foodResolutionReview(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct CustomFoodImportView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss

    @State private var food: CustomFoodDefinition
    @State private var saveForReuse = false

    init(file: CustomFoodFile) {
        _food = State(initialValue: file.food)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    ImportedFoodFields(food: $food)
                }

                Section {
                    Toggle("Save to Custom foods", isOn: $saveForReuse)
                } footer: {
                    Text(saveForReuse
                        ? "The food will be logged today and remain available for reuse."
                        : "The food will be logged today as a one-off and won’t clutter your Custom catalog.")
                }

                loggingUnavailableSection
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Review Imported Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", action: logFood)
                        .disabled(!canLog)
                }
            }
            .analyticsScreen("food_import_review")
        }
    }

    @ViewBuilder
    private var loggingUnavailableSection: some View {
        if !diary.canLogFood(on: Date()) {
            Section {
                Label("Food can’t be logged while today is marked as a cheat day.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canLog: Bool {
        (try? food.validate()) != nil && diary.canLogFood(on: Date())
    }

    private func logFood() {
        diary.run {
            guard canLog else { return }
            let previousEntryCount = diary.entries(on: Date()).count
            let loggedFood = try await diary.logImportedFood(food.normalized().makeFood(), saveForReuse: saveForReuse, on: Date())
            if saveForReuse {
                AppAnalytics.capture("custom_food.created", properties: ["origin": "file_import"])
            }
            if diary.entries(on: Date()).count > previousEntryCount {
                AppAnalytics.capture(
                    "food_log.completed",
                    properties: FoodLogAnalytics.foodProperties(
                        food: loggedFood,
                        method: "file_import",
                        mode: "import",
                        unit: .serving,
                        isFavorite: diary.isFavorite(loggedFood),
                        foodKind: saveForReuse ? "imported" : "one_off",
                        savedForReuse: saveForReuse
                    )
                )
            }
            dismiss()

        }
    }
}

struct CustomMealImportView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss

    private let originalNotes: String?
    @State private var name: String
    @State private var foods: [CustomFoodDefinition]
    @State private var saveForReuse = false

    init(file: CustomMealFile) {
        originalNotes = file.notes
        _name = State(initialValue: file.name)
        _foods = State(initialValue: file.foods)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                    if let originalNotes {
                        Text(originalNotes)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Calculated total") {
                    nutrientTotal("Calories", totalNutrients.calories)
                    nutrientTotal("Carbohydrates", totalNutrients.carbs, suffix: " g")
                    nutrientTotal("Fat", totalNutrients.fat, suffix: " g")
                    nutrientTotal("Protein", totalNutrients.protein, suffix: " g")
                    if let fiber = totalNutrients.fiber {
                        nutrientTotal("Fiber", fiber, suffix: " g")
                    }
                }

                ForEach(Array(foods.indices), id: \.self) { index in
                    Section("Food \(index + 1)") {
                        ImportedFoodFields(food: $foods[index])
                    }
                }

                Section {
                    Toggle("Save to Saved meals", isOn: $saveForReuse)
                } footer: {
                    Text(saveForReuse
                        ? "The meal will be logged today and remain available for reuse."
                        : "The meal will be logged today as a one-off. Its foods can still be inspected or broken apart from the diary entry.")
                }

                if !diary.canLogFood(on: Date()) {
                    Section {
                        Label("Food can’t be logged while today is marked as a cheat day.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Review Imported Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", action: logMeal)
                        .disabled(!canLog)
                }
            }
            .analyticsScreen("meal_import_review")
        }
    }

    private var reviewedFile: CustomMealFile {
        CustomMealFile(
            format: CustomMealFile.formatIdentifier,
            version: CustomMealFile.currentVersion,
            name: name,
            foods: foods,
            notes: originalNotes
        )
    }

    private var totalNutrients: MacroNutrients {
        reviewedFile.makeMeal().nutrients
    }

    private var canLog: Bool {
        (try? reviewedFile.validate()) != nil && diary.canLogFood(on: Date())
    }

    private func nutrientTotal(_ title: String, _ value: Double, suffix: String = "") -> some View {
        LabeledContent(title) {
            Text(value.cleanAmount + suffix)
                .monospacedDigit()
        }
    }

    private func logMeal() {
        diary.run {
            guard canLog else { return }
            let importedMeal = reviewedFile.makeMeal()
            let previousEntryCount = diary.entries(on: Date()).count
            let loggedMeal = try await diary.logImportedMeal(importedMeal, on: Date())
            if saveForReuse {
                AppAnalytics.capture("meal.created", properties: [
                    "origin": "file_import", "item_count": String(importedMeal.items.count)
                ])
            }
            if diary.entries(on: Date()).count > previousEntryCount {
                AppAnalytics.capture(
                    "food_log.completed",
                    properties: FoodLogAnalytics.mealProperties(
                        meal: loggedMeal,
                        method: "file_import",
                        mode: "import",
                        isFavorite: saveForReuse && diary.isFavorite(loggedMeal),
                        foodKind: "imported",
                        includeLocalID: true,
                        savedForReuse: saveForReuse
                    )
                )
            }
            dismiss()

        }
    }
}

struct CustomImportGuideView: View {
    @State private var copiedPrompt = false

    var body: some View {
        List {
            Section {
                step(1, "Send a food photo and any useful context to ChatGPT or another assistant.")
                step(2, "Paste the prompt below. It creates a .calfood by default, or a .calmeal only when you explicitly request separate foods.")
                step(3, "Open or share the attachment to Yum Chase, review the estimate, and tap Log.")
            } header: {
                Text("How it works")
            } footer: {
                Text("Only the small food or meal file is handed to Yum Chase. The app does not receive a chat link or access your conversation.")
            }

            Section("Format prompt") {
                Text(CustomImportFile.assistantPrompt)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = CustomImportFile.assistantPrompt
                    copiedPrompt = true
                } label: {
                    Label(copiedPrompt ? "Copied" : "Copy Prompt", systemImage: copiedPrompt ? "checkmark" : "doc.on.doc")
                }
            }
        }
        .navigationTitle("AI Import")
        .analyticsScreen("import_guide")
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number.formatted())
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppTheme.coral, in: Circle())
            Text(text)
        }
        .padding(.vertical, 2)
    }
}

private struct ImportedFoodFields: View {
    @Binding var food: CustomFoodDefinition

    var body: some View {
        TextField("Name", text: $food.name)
        TextField("Serving description", text: $food.servingDescription)
        decimalField("Estimated serving weight (g)", value: $food.servingGrams)
        decimalField("Calories", value: $food.nutrition.calories)
        decimalField("Carbohydrates (g)", value: $food.nutrition.carbohydratesGrams)
        decimalField("Fat (g)", value: $food.nutrition.fatGrams)
        decimalField("Protein (g)", value: $food.nutrition.proteinGrams)
        optionalDecimalField("Fiber (g, optional)", value: $food.nutrition.fiberGrams)
        FoodMeatFields(name: food.name,
            processed: Binding(get: { food.containsProcessedMeat }, set: {
                food.containsProcessedMeat = $0; food.processedMeatWasEdited = true
            }),
            red: Binding(get: { food.containsRedMeat }, set: {
                food.containsRedMeat = $0; food.redMeatWasEdited = true
            }))
        TextField("Notes (optional)", text: notesBinding, axis: .vertical)
            .lineLimit(2...5)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { food.notes ?? "" },
            set: { food.notes = $0.isEmpty ? nil : $0 }
        )
    }

    private func decimalField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    private func optionalDecimalField(_ title: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

}
