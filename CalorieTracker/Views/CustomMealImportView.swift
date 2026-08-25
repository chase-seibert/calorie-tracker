import SwiftUI
import UIKit

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
        guard canLog else { return }
        let definition = food.normalized()
        let loggedFood: Food
        if saveForReuse {
            loggedFood = diary.addCustomFood(
                name: definition.name,
                brand: "",
                calories: definition.nutrition.calories,
                carbs: definition.nutrition.carbohydratesGrams,
                fat: definition.nutrition.fatGrams,
                protein: definition.nutrition.proteinGrams,
                servingGrams: definition.servingGrams,
                servingDescription: "1 \(definition.servingDescription)"
            )
        } else {
            loggedFood = definition.makeFood()
        }

        diary.log(
            loggedFood,
            amount: 1,
            unit: .serving,
            portionID: loggedFood.availablePortions.first?.id,
            on: Date()
        )
        dismiss()
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
        guard canLog else { return }
        let importedMeal = reviewedFile.makeMeal()
        if saveForReuse {
            guard let savedMeal = diary.saveMeal(name: importedMeal.name, items: importedMeal.items) else {
                return
            }
            diary.logMeal(savedMeal, on: Date())
        } else {
            diary.logOneOffMeal(importedMeal, on: Date())
        }
        dismiss()
    }
}

struct CustomImportGuideView: View {
    @State private var copiedPrompt = false

    var body: some View {
        List {
            Section {
                step(1, "Send a food photo and any useful context to ChatGPT or another assistant.")
                step(2, "Paste the prompt below. It creates a .calfood by default, or a .calmeal only when you explicitly request separate foods.")
                step(3, "Open or share the attachment to Calorie Tracker, review the estimate, and tap Log.")
            } header: {
                Text("How it works")
            } footer: {
                Text("Only the small food or meal file is handed to Calorie Tracker. The app does not receive a chat link or access your conversation.")
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
}
