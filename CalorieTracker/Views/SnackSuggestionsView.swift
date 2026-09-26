import SwiftUI

struct SnackSuggestionsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    @AppStorage("trends.focus.fiber") private var tracksFiber = true
    @AppStorage("trends.focus.processedMeat") private var tracksProcessedMeat = true
    @AppStorage("trends.focus.redMeat") private var tracksRedMeat = true
    @StateObject private var reminders = SnackRemindersStore()
    @State private var selectedIDs = Set<String>()
    @State private var showingLists = false

    private var preferences: SnackFocusPreferences {
        .init(fiber: tracksFiber, processedMeat: tracksProcessedMeat, redMeat: tracksRedMeat, alcohol: tracksAlcohol)
    }

    private var snacks: [SnackSuggestion] { SnackSuggestions.snacks(for: preferences) }
    private var selectedSnacks: [SnackSuggestion] {
        SnackSuggestions.selectedSnacks(in: snacks, ids: selectedIDs)
    }

    var body: some View {
        List {
            Section {
                Text("Snack ideas filtered to your focus areas, with high-protein picks always included. Each snack appears once.")
                if tracksProcessedMeat || tracksRedMeat {
                    Label(exclusionDescription, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Ideas are curated on-device. Each snack appears once, even when it supports multiple focus areas.")
            }

            remindersSection

            Section {
                ForEach(snacks) { snack in
                    snackRow(snack)
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("The badges show which enabled focus areas each snack supports.")
            }

            Section("About These Ideas") {
                Text("Adjust portions to your appetite and calorie goal. Check labels and ingredients for your allergies or dietary needs; these suggestions don't know them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("CDC: Healthier Meals & Snacks", destination: URL(string: "https://www.cdc.gov/healthy-weight-growth/healthy-eating/meals-snacks.html")!)
                Link("NIH: Food Sources of Fiber", destination: URL(string: "https://medlineplus.gov/ency/patientinstructions/000193.htm")!)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Snack Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("settings_snack_suggestions")
        .onAppear { reminders.refreshLists() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reminders.refreshLists() }
        }
        .onChange(of: preferences) { _, _ in
            selectedIDs.formIntersection(snacks.map(\.id))
        }
        .sheet(isPresented: $showingLists) { listPicker }
        .alert("Couldn't Update Reminders", isPresented: Binding(
            get: { reminders.errorMessage != nil },
            set: { if !$0 { reminders.clearError() } }
        )) {
            Button("OK", role: .cancel) { reminders.clearError() }
        } message: {
            Text(reminders.errorMessage ?? "")
        }
    }

    private var exclusionDescription: String {
        if tracksProcessedMeat && tracksRedMeat { return "Processed meat and red meat excluded from all suggestions." }
        return tracksProcessedMeat ? "Processed meat excluded from all suggestions." : "Red meat excluded from all suggestions."
    }

    private var remindersSection: some View {
        Section {
            Button {
                Task {
                    if await reminders.prepareListChoice() { showingLists = true }
                }
            } label: {
                HStack {
                    Label(reminders.selectedList?.title ?? "Choose Reminders List", systemImage: "list.bullet")
                    Spacer()
                    if reminders.selectedList != nil { Text("Change").foregroundStyle(.secondary) }
                }
            }
            .disabled(reminders.isBusy)

            HStack {
                Text("\(selectedSnacks.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(selectedSnacks.isEmpty ? "Select All" : "Clear") {
                    if selectedSnacks.isEmpty {
                        selectedIDs = Set(snacks.map(\.id))
                    } else {
                        selectedIDs.removeAll()
                    }
                }
                .disabled(reminders.isBusy)
            }

            Button {
                let snacks = selectedSnacks
                Task {
                    if await reminders.add(snacks) { selectedIDs.subtract(snacks.map(\.id)) }
                }
            } label: {
                HStack {
                    Label("Add Selected to Reminders", systemImage: "checklist")
                    if reminders.isBusy { Spacer(); ProgressView() }
                }
            }
            .disabled(selectedSnacks.isEmpty || reminders.selectedList == nil || reminders.isBusy)

            if let message = reminders.statusMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.protein)
                    .accessibilityIdentifier("snacks.reminders.result")
            }
        } header: {
            Text("Shopping List")
        } footer: {
            Text("Choose a list once; change it anytime. Only Add sends selected snack names and Log Food links to Reminders. Incomplete matches are skipped. Reminders may sync or be visible to others if you choose a shared list. Your diary and focus settings aren't shared.")
        }
    }

    private func snackRow(_ snack: SnackSuggestion) -> some View {
        let areas = SnackFocusArea.allCases.filter { preferences.includes($0) && snack.reasons[$0] != nil }
        return Button {
            if !selectedIDs.insert(snack.id).inserted { selectedIDs.remove(snack.id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedIDs.contains(snack.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(snack.id) ? AppTheme.protein : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(snack.name).font(.headline).foregroundStyle(.primary)
                    Text(areas.map(\.badgeTitle).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.protein)
                    Text(snack.reasons[areas.first ?? .protein] ?? "").foregroundStyle(.primary)
                    Text(snack.servingTip).font(.caption).foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reminders.isBusy)
        .accessibilityIdentifier("snack.\(snack.id)")
        .accessibilityValue(selectedIDs.contains(snack.id) ? "Selected" : "Not selected")
        .accessibilityHint("Select for your Reminders shopping list")
    }

    private var listPicker: some View {
        NavigationStack {
            List {
                if reminders.lists.isEmpty {
                    ContentUnavailableView("No Writable Lists", systemImage: "list.bullet", description: Text("Create a list in Apple Reminders, then return and choose it here. Smart lists and read-only lists can't receive new reminders."))
                } else {
                    Section {
                        ForEach(reminders.lists) { list in
                            Button {
                                reminders.choose(list)
                                showingLists = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(list.title).foregroundStyle(.primary)
                                        Text(list.account).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if reminders.selectedList?.id == list.id {
                                        Image(systemName: "checkmark").accessibilityLabel("Selected")
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text("This choice is saved for next time. Selecting a list doesn't add anything. A shared list may be visible to other people.")
                    }
                }
            }
            .navigationTitle("Reminders List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingLists = false }
                }
            }
        }
    }
}
