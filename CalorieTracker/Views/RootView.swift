import SwiftUI

struct RootView: View {
    let catalog: CatalogStore
    @EnvironmentObject private var diary: DiaryStore
    @ObservedObject private var quickActionRouter = HomeScreenQuickActionRouter.shared
    @AppStorage(FirstTimeOnboarding.completedKey) private var completedFocusOnboarding = false
    @State private var importRequest: ImportRequest?
    @State private var importError: String?

    var body: some View {
        DiaryView(catalog: catalog)
            .onOpenURL(perform: openImportFile)
            .sheet(item: $importRequest) { request in
                switch request.file {
                case let .food(file):
                    CustomFoodImportView(file: file)
                case let .meal(file):
                    CustomMealImportView(file: file)
                }
            }
            .alert("Couldn’t Import File", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Unknown error")
            }
            .onReceive(quickActionRouter.$request.compactMap { $0 }) { request in
                handleQuickAction(request)
            }
            .fullScreenCover(isPresented: Binding(
                get: { !completedFocusOnboarding },
                set: { _ in }
            )) {
                FocusOnboardingView()
                    .interactiveDismissDisabled()
            }
    }

    private func openImportFile(_ url: URL) {
        do {
            let importedFile = try CustomImportFile.load(from: url)
            importRequest = ImportRequest(file: importedFile)
            importError = nil
            let itemType: String = switch importedFile {
            case .food: "food"
            case .meal: "meal"
            }
            AppAnalytics.capture("import.opened", properties: ["item_type": itemType])
        } catch {
            importRequest = nil
            importError = error.localizedDescription
            AppAnalytics.capture("import.failed")
        }
    }

    private func handleQuickAction(_ request: HomeScreenQuickActionRequest) {
        defer { quickActionRouter.consume(request) }
        guard let result = diary.logQuickSelection(request.selectionID) else { return }
        AppAnalytics.capture("diary.quick_action_logged", properties: [
            "item_count": String(result.loggedItemCount)
        ])
    }
}

private struct ImportRequest: Identifiable {
    let id = UUID()
    let file: CustomImportFile
}

private struct FocusOnboardingView: View {
    @AppStorage(FirstTimeOnboarding.completedKey) private var completed = false
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    @AppStorage("trends.focus.fiber") private var tracksFiber = true
    @AppStorage("trends.focus.processedMeat") private var tracksProcessedMeat = true
    @AppStorage("trends.focus.redMeat") private var tracksRedMeat = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "scope")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(AppTheme.coral)
                            .frame(width: 72, height: 72)
                            .background(AppTheme.coral.opacity(0.14), in: Circle())

                        Text("What do you want to focus on?")
                            .font(.largeTitle.bold())

                        Text("Calories and macros are always included. Choose any additional areas you want VitaChase to emphasize.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        focusButton(
                            title: "Alcohol",
                            description: "Quick drink logging and alcohol trends",
                            systemImage: "wineglass",
                            color: AppTheme.fat,
                            isSelected: tracksAlcohol
                        ) {
                            tracksAlcohol.toggle()
                        }
                        focusButton(
                            title: "Fiber",
                            description: "Daily fiber intake and 30-day trends",
                            systemImage: "leaf.fill",
                            color: AppTheme.fiber,
                            isSelected: tracksFiber
                        ) {
                            tracksFiber.toggle()
                        }
                        focusButton(
                            title: "Processed Meat",
                            description: "Track which days include processed meat",
                            systemImage: "chart.bar.fill",
                            color: AppTheme.processedMeat,
                            isSelected: tracksProcessedMeat
                        ) {
                            tracksProcessedMeat.toggle()
                        }
                        focusButton(
                            title: "Red Meat",
                            description: "Track which days include unprocessed red meat",
                            systemImage: "chart.bar.fill",
                            color: AppTheme.redMeat,
                            isSelected: tracksRedMeat
                        ) {
                            tracksRedMeat.toggle()
                        }
                    }

                    Text("You can change these choices anytime under Settings → Focus Areas.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 120)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                Button {
                    completed = true
                } label: {
                    Text("Start Tracking")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.coral)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .analyticsScreen("onboarding_focus")
    }

    private func focusButton(
        title: String,
        description: String,
        systemImage: String,
        color: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.coral : Color.secondary)
            }
            .padding(16)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? AppTheme.coral.opacity(0.65) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
