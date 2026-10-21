import SwiftUI

struct RootView: View {
    let catalog: CatalogStore
    @Binding var pendingOpenURL: URL?
    @EnvironmentObject private var diary: DiaryStore
    @ObservedObject private var quickActionRouter = HomeScreenQuickActionRouter.shared
    @AppStorage(FirstTimeOnboarding.completedKey) private var completedFocusOnboarding = false
    @State private var foodPickerLaunch = FoodPickerLaunch.initialLaunch
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var homeViewID = UUID()
    @State private var showingWeeklyReport = false

    var body: some View {
        DiaryView(catalog: catalog, foodPickerLaunch: $foodPickerLaunch)
            .id(homeViewID)
            .disabled(diary.isLoading || diary.isSaving || !diary.hasLoadedSnapshot)
            .overlay {
                if diary.isLoading {
                    ProgressView("Opening diary…").padding().background(
                        .regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if !diary.hasLoadedSnapshot {
                    ContentUnavailableView {
                        Label("Diary unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(
                            "Your existing data has not been replaced. Retry opening it after resolving the storage issue."
                        )
                    } actions: {
                        Button("Retry") { Task { await diary.reloadFromDisk() } }
                    }.background(AppTheme.background)
                }
            }
            .alert(
                "Diary unavailable",
                isPresented: Binding(
                    get: { diary.lastSaveError != nil },
                    set: { if !$0 { diary.dismissSaveError() } }
                )
            ) {
                Button("Retry") { Task { await diary.reloadFromDisk() } }
                Button("OK", role: .cancel) { diary.dismissSaveError() }
            } message: {
                Text(diary.lastSaveError ?? "Your diary could not be opened.")
            }
            .task(id: diary.hasLoadedSnapshot ? pendingOpenURL : nil) {
                guard diary.hasLoadedSnapshot, let url = pendingOpenURL else { return }
                pendingOpenURL = nil
                handleOpenURL(url)
            }
            .sheet(item: $importRequest) { request in
                CustomMealImportView(file: request.file)
            }
            .fullScreenCover(isPresented: $showingWeeklyReport) {
                NavigationStack {
                    WeeklyFoodReportView()
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingWeeklyReport = false } } }
                }
                .environmentObject(diary)
            }
            .alert(
                "Couldn’t Import File",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Unknown error")
            }
            .onReceive(quickActionRouter.$request.compactMap { $0 }) { request in
                handleQuickAction(request)
            }
            .onReceive(NotificationCenter.default.publisher(for: FirstTimeOnboarding.resetNotification)) { _ in
                homeViewID = UUID()
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: {
                        !completedFocusOnboarding && !diary.isLoading && diary.hasLoadedSnapshot
                            && diary.lastSaveError == nil
                    },
                    set: { _ in }
                )
            ) {
                FirstTimeOnboardingView()
                    .interactiveDismissDisabled()
            }
    }

    private func handleOpenURL(_ url: URL) {
        if VitaChaseDeepLink(url: url) == .logFood {
            foodPickerLaunch = .search
            AppAnalytics.capture("widget.opened_log_food")
            return
        }
        if VitaChaseDeepLink(url: url) == .weeklyReport {
            showingWeeklyReport = true
            return
        }
        openImportFile(url)
    }

    private func openImportFile(_ url: URL) {
        do {
            let importedFile = try CustomImportFile.load(from: url)
            importRequest = ImportRequest(file: importedFile)
            importError = nil
            AppAnalytics.capture("import.opened", properties: ["item_type": "meal"])
        } catch {
            importRequest = nil
            importError = error.localizedDescription
            AppAnalytics.capture("import.failed")
        }
    }

    private func handleQuickAction(_ request: HomeScreenQuickActionRequest) {
        diary.run {
            defer { quickActionRouter.consume(request) }
            guard let result = try await diary.logQuickSelection(request.selectionID) else { return }
            AppAnalytics.capture(
                "diary.quick_action_logged",
                properties: [
                    "item_count": String(result.loggedItemCount)
                ])

        }
    }
}

private struct ImportRequest: Identifiable {
    let id = UUID()
    let file: CustomMealFile
}

private struct FirstTimeOnboardingView: View {
    @State private var step: OnboardingStep = .focus
    @AppStorage(FirstTimeOnboarding.completedKey) private var completed = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .focus:
                    FocusOnboardingStep { step = .tracking }
                case .tracking:
                    TrackingConceptsOnboardingStep(onBack: goBack, onContinue: advance)
                case .magic:
                    MagicOnboardingStep(onBack: goBack, onContinue: advance)
                case .calorieGoal:
                    CalorieGoalOnboardingStep(onBack: goBack, onContinue: advance)
                case .health:
                    AppleHealthOnboardingStep(onBack: goBack, onContinue: advance)
                case .history:
                    HistoryImportOnboardingStep(onBack: goBack, onContinue: finish)
                }
            }
        }
        .background(AppTheme.background)
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1), previous != .focus else {
            step = .focus
            return
        }
        step = previous
    }

    private func finish() {
        completed = true
    }
}

private enum OnboardingStep: Int, Equatable {
    case focus, tracking, magic, calorieGoal, health, history
}

private struct FocusOnboardingStep: View {
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    @AppStorage("trends.focus.fiber") private var tracksFiber = true
    @AppStorage("trends.focus.processedMeat") private var tracksProcessedMeat = true
    @AppStorage("trends.focus.redMeat") private var tracksRedMeat = true

    let onContinue: () -> Void

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What do you want to focus on?").font(.title.bold())
                    Text("Calories and macros are always included. Choose any additional areas you want Yum Chase to emphasize.")
                        .font(.body).foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    focusButton("Alcohol", "Track drinks", "wineglass", AppTheme.fat, tracksAlcohol) { tracksAlcohol.toggle() }
                    focusButton("Fiber", "Daily fiber", "leaf.fill", AppTheme.fiber, tracksFiber) { tracksFiber.toggle() }
                    focusButton("Processed Meat", "Processed meat", "chart.bar.fill", AppTheme.processedMeat, tracksProcessedMeat) { tracksProcessedMeat.toggle() }
                    focusButton("Red Meat", "Track red meat", "chart.bar.fill", AppTheme.redMeat, tracksRedMeat) { tracksRedMeat.toggle() }
                }
                Text("You can change these choices anytime under Settings → Focus Areas.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 110)
        }
        .background(AppTheme.background)
        .overlay(alignment: .bottomTrailing) {
            OnboardingNextButton(action: onContinue)
                .padding(.trailing, 18)
                .padding(.bottom, 20)
        }
        .analyticsScreen("onboarding_focus")
    }

    private func focusButton(_ title: String, _ description: String, _ systemImage: String, _ color: Color, _ isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.title3.weight(.semibold)).foregroundStyle(color)
                    .frame(width: 42, height: 42).background(color.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(description).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(isSelected ? AppTheme.coral : Color.secondary)
            }
            .padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(isSelected ? AppTheme.coral.opacity(0.65) : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain).accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct CalorieGoalOnboardingStep: View {
    @EnvironmentObject private var diary: DiaryStore
    @FocusState private var goalIsFocused: Bool
    @State private var goalText = ""
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(icon: "target", title: "Set a daily calorie goal", message: "An optional goal makes your diary and widgets show how many calories you have left or how far over you are. You can change it anytime in Settings.", analyticsName: "onboarding_calorie_goal", onBack: onBack, onContinue: continueFromGoal) {
            HStack(spacing: 12) {
                TextField("Example: 2,000", text: $goalText).keyboardType(.numberPad).focused($goalIsFocused)
                    .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 110)
                Text("calories / day").foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if goalText.isEmpty, let goal = diary.dailyCalorieGoal { goalText = goal.formatted() }
        }
    }

    private func continueFromGoal() {
        diary.run {
            let digits = goalText.filter(\.isNumber)
            if let value = Int(digits), value > 0 {
                try await diary.setDailyCalorieGoal(value)
            }
            goalIsFocused = false
            onContinue()

        }
    }
}

private struct HistoryImportOnboardingStep: View {
    @State private var showingImportGuide = false
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(icon: "arrow.down.doc", title: "Import food and meal estimates", message: "Import AI generated food and meal estimates as a .calmeal file. Your data stays on this device.", analyticsName: "onboarding_history_import", onBack: onBack, onContinue: onContinue) {
            HStack {
                Spacer()
                Button { showingImportGuide = true } label: { Label("Open import guide", systemImage: "book.pages") }
                    .buttonStyle(.bordered)
                Spacer()
            }
            Text("You can also find this guide later under Settings → AI Food & Meal Import.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingImportGuide) {
            NavigationStack {
                CustomImportGuideView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingImportGuide = false } } }
            }
        }
    }
}

private struct AppleHealthOnboardingStep: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var healthKit: HealthKitStore
    @State private var connecting = false
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(icon: "heart.fill", title: "Connect Apple Health", message: "Yum Chase can write calories, macros, and fiber from your logged foods and meals to Apple Health. This is optional and can be changed in Settings.", analyticsName: "onboarding_apple_health", onBack: onBack, onContinue: onContinue) {
            if healthKit.authorizationState == .authorized {
                Label("Apple Health connected", systemImage: "checkmark.circle.fill").foregroundStyle(AppTheme.protein)
            } else if healthKit.isAvailable {
                Button { Task { await connect() } } label: {
                    if connecting { ProgressView() } else { Label("Connect Apple Health", systemImage: "heart.fill") }
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.coral).disabled(connecting)
            } else {
                Label("Apple Health is unavailable on this device", systemImage: "heart.slash").foregroundStyle(.secondary)
            }
        }
    }

    private func connect() async {
        connecting = true
        healthKit.clearLastError()
        await healthKit.requestAuthorizationAndSync(entries: [])
        if healthKit.authorizationState == .authorized {
            await diary.syncAllHealthData()
            await healthKit.waitForPendingOperations()
        }
        connecting = false
    }
}

private struct TrackingConceptsOnboardingStep: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(icon: "calendar.badge.clock", title: "Understand your tracking days", message: "A little context helps the trends make sense.", analyticsName: "onboarding_tracking_concepts", onBack: onBack, onContinue: onContinue) {
            conceptRow("sparkles", "Cheat days", "A planned higher-calorie day. Yum Chase keeps the adjustment visible so your weekly picture stays honest.")
            conceptRow("minus.circle", "Gap days", "A day with no food or meal log. It is left blank rather than counted as a success or failure.")
            conceptRow("wineglass", "Alcohol", "Drinks are tracked separately, while their estimated calories still count toward the day’s total.")
        }
    }

    private func conceptRow(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).foregroundStyle(AppTheme.coral).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MagicOnboardingStep: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(icon: "wand.and.stars", title: "Meet Magic mode", message: "Magic learns the foods and meals you repeat over the last 10 days, then puts the right suggestions in front of you at breakfast, lunch, or dinner.", analyticsName: "onboarding_magic", onBack: onBack, onContinue: onContinue) {
            magicStep(1, "Open Log Food", "Choose the Magic tab or use a home-screen shortcut.")
            magicStep(2, "Pick a suggestion", "A single tap logs the remembered amount immediately—no confirmation dialog.")
            magicStep(3, "Keep building your routine", "Magic looks at your recent pattern and improves as you log.")
        }
    }

    private func magicStep(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number.formatted()).font(.headline).foregroundStyle(.white).frame(width: 30, height: 30).background(
                AppTheme.coral, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let icon: String
    let title: String
    let message: String
    let analyticsName: String
    let onBack: () -> Void
    let onContinue: () -> Void
    let content: Content

    init(
        icon: String,
        title: String,
        message: String,
        analyticsName: String,
        onBack: @escaping () -> Void,
        onContinue: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.analyticsName = analyticsName
        self.onBack = onBack
        self.onContinue = onContinue
        self.content = content()
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: icon).font(.system(size: 32, weight: .semibold)).foregroundStyle(AppTheme.coral)
                            .frame(width: 60, height: 60).background(AppTheme.coral.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(.title.bold())
                            Text(message).font(.body).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                }
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 110)
            }
        }
        .background(AppTheme.background)
        .overlay(alignment: .bottomTrailing) {
            OnboardingNextButton(action: onContinue)
                .padding(.trailing, 18)
                .padding(.bottom, 20)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(AppTheme.coral)
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: onContinue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .analyticsScreen(analyticsName)
    }
}

private struct OnboardingNextButton: View {
    let action: () -> Void

    var body: some View {
        Button("Next", action: action)
            .font(.headline)
            .padding(.horizontal, 16)
            .frame(minWidth: 132, minHeight: 52)
            .foregroundStyle(.white)
            .background(AppTheme.coral, in: Capsule())
    }
}
