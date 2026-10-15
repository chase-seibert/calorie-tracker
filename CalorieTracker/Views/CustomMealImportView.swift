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
        let selected = choice.wrappedValue ?? suggested
        return VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(AppTheme.ink)
            HStack(spacing: 8) {
                valuePill("Yes", selected: selected == true, title: title) { choice.wrappedValue = true }
                valuePill("No", selected: selected == false, title: title) { choice.wrappedValue = false }
            }
        }
    }

    private func valuePill(_ label: String, selected: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(selected ? AppTheme.coral : AppTheme.controlFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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

struct CustomMealImportView: View {
    enum Source: Equatable {
        case fileImport
        case openAIAnalysis

        var analyticsMethod: String { self == .fileImport ? "file_import" : "openai_meal_analysis" }
        var navigationTitle: String { self == .fileImport ? "Review Imported Meal" : "Review Meal" }
    }

    let file: CustomMealFile
    let targetDate: Date
    let source: Source
    let onLogged: (() -> Void)?
    @EnvironmentObject private var diary: DiaryStore
    init(file: CustomMealFile, targetDate: Date = Date(), source: Source = .fileImport, onLogged: (() -> Void)? = nil) {
        self.file = file; self.targetDate = targetDate; self.source = source; self.onLogged = onLogged
    }
    var body: some View {
        MealDetailView(context: .imported(file, targetDate, source, onLogged), catalog: diary.foodCatalog)
    }
}

struct CustomImportGuideView: View {
    @State private var copiedPrompt = false

    var body: some View {
        List {
            Section {
                step(1, "Send a food photo and any useful context to ChatGPT or another assistant.")
                step(2, "Paste the prompt below. It always creates one named .calmeal with one or more food components.")
                step(3, "Open or share the attachment to Yum Chase, review the estimate, and tap Log.")
            } header: {
                Text("How it works")
            } footer: {
                Text("Only the small .calmeal file is handed to Yum Chase. The app does not receive a chat link or access your conversation.")
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

struct ImportedFoodFields: View {
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
