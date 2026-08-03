import SwiftUI

struct DiaryView: View {
    @EnvironmentObject private var diary: DiaryStore
    let catalog: CatalogStore

    @State private var dayOffset = 0
    @State private var showingFoodPicker = ProcessInfo.processInfo.arguments.contains("--show-food-search")
    @State private var showingMealName = false
    @State private var mealName = ""
    @State private var isSelectingMealItems = false
    @State private var selectedEntryIDs: Set<UUID> = []

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
                        MacroSummary(nutrients: diary.totals(on: date))
                        entrySection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Calorie Tracker")
            .toolbar {
                if isSelectingMealItems {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancelMealSelection() }
                    }
                }
                if !diary.entries(on: date).isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isSelectingMealItems {
                            Button("Next (\(selectedEntryIDs.count))") {
                                mealName = ""
                                showingMealName = true
                            }
                            .disabled(selectedEntryIDs.isEmpty)
                        } else {
                            Button("Save meal", systemImage: "square.stack.3d.up") {
                                selectedEntryIDs = []
                                isSelectingMealItems = true
                            }
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
            .alert("Save selected foods as a meal", isPresented: $showingMealName) {
                TextField("Meal name", text: $mealName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveSelectedAsMeal() }
                    .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Only the \(selectedEntryIDs.count) selected item\(selectedEntryIDs.count == 1 ? "" : "s") will be saved together.")
            }
            .onChange(of: dayOffset) { _, _ in cancelMealSelection() }
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
                Text("\(entries.count) item\(entries.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
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
                        DiaryEntryRow(entry: entry)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    diary.delete(entryID: entry.id)
                                }
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    diary.delete(entryID: entry.id)
                                }
                            }
                    }
                }
            }
        }
    }

    private func saveSelectedAsMeal() {
        let items = diary.entries(on: date).filter { selectedEntryIDs.contains($0.id) }.map {
            MealItem(
                id: UUID(),
                food: $0.food,
                amount: $0.amount,
                unit: $0.unit,
                portionID: $0.portionID
            )
        }
        diary.saveMeal(name: mealName.trimmingCharacters(in: .whitespacesAndNewlines), items: items)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Int(nutrients.calories.rounded()).formatted())
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("calories")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                }
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

    var body: some View {
        HStack(spacing: 12) {
            SourceBadge(source: entry.food.source)
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
