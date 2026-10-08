import AppIntents
import SwiftUI
import WidgetKit

struct QuickLogWidgetEntry: TimelineEntry {
    let date: Date
    let selections: [QuickLogSelection]
    let caloriesRemaining: Int?
    let receipt: QuickLogReceipt?
    let pendingSelectionID: String?
}

struct QuickLogWidgetProvider: TimelineProvider {
    private let receiptDisplayDuration: TimeInterval = 10 * 60

    func placeholder(in context: Context) -> QuickLogWidgetEntry {
        QuickLogWidgetEntry(
            date: Date(),
            selections: [
                QuickLogSelection(
                    id: "preview",
                    title: "Cappuccino",
                    subtitle: "120 cal",
                    itemIDs: ["preview"]
                )
            ],
            caloriesRemaining: 1_240,
            receipt: nil,
            pendingSelectionID: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogWidgetEntry>) -> Void) {
        let now = Date()
        var dates = [now] + upcomingMagicBoundaries(after: now)
        if let receipt = SharedDiaryStorage.latestQuickLogReceipt() {
            let expiry = receipt.loggedAt.addingTimeInterval(receiptDisplayDuration)
            if expiry > now { dates.append(expiry) }
        }
        let uniqueDates = Array(Set(dates)).sorted()
        completion(Timeline(entries: uniqueDates.map(entry(at:)), policy: .atEnd))
    }

    private func entry(at date: Date) -> QuickLogWidgetEntry {
        guard let snapshot = try? QuickLogRepository().snapshot() else {
            return QuickLogWidgetEntry(
                date: date,
                selections: [],
                caloriesRemaining: nil,
                receipt: recentReceipt(at: date),
                pendingSelectionID: QuickLogWidgetActionState.pendingSelectionID(at: date)
            )
        }
        return QuickLogWidgetEntry(
            date: date,
            selections: snapshot.widgetSelections(at: date, limit: 10),
            caloriesRemaining: try? snapshot.caloriesRemaining(at: date),
            receipt: recentReceipt(at: date),
            pendingSelectionID: QuickLogWidgetActionState.pendingSelectionID(at: date)
        )
    }

    private func recentReceipt(at date: Date) -> QuickLogReceipt? {
        guard let receipt = SharedDiaryStorage.latestQuickLogReceipt() else { return nil }
        let elapsed = date.timeIntervalSince(receipt.loggedAt)
        return elapsed >= -5 && elapsed < receiptDisplayDuration ? receipt : nil
    }

    private func upcomingMagicBoundaries(after date: Date) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        return (0...2).flatMap { dayOffset -> [Date] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else {
                return []
            }
            return [5, 11, 15].compactMap { hour in
                calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            }
        }
        .filter { $0 > date }
        .prefix(6)
        .map { $0 }
    }
}

struct QuickLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickLogWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularContent
            case .accessoryRectangular:
                lockScreenContent
            case .systemLarge:
                largeContent
            default:
                mediumContent
            }
        }
        .widgetURL(VitaChaseDeepLink.logFoodURL)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                header
                Spacer()
                calorieLabel
            }
            if entry.selections.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(entry.selections.prefix(4)) { selection in
                        quickLogButton(selection, compact: true)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .containerBackground(.background, for: .widget)
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                header
                Spacer()
                calorieLabel
            }
            if entry.selections.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(entry.selections.prefix(10)) { selection in
                        quickLogButton(selection, compact: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .containerBackground(.background, for: .widget)
    }

    private var circularContent: some View {
        Link(destination: VitaChaseDeepLink.logFoodURL) {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus.circle.fill")
                    .font(.title)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Log Food in Yum Chase")
        .containerBackground(.clear, for: .widget)
    }

    private var lockScreenContent: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.receipt == nil ? "sparkles" : "checkmark.circle.fill")
            if let receipt = entry.receipt {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Logged")
                        .font(.headline)
                    Text(receipt.title)
                        .font(.caption)
                        .lineLimit(1)
                }
            } else if let selection = entry.selections.first {
                Button(intent: LogRecentItemIntent(item: QuickLogSelectionEntity(selection: selection))) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selection.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Tap to log · \(selection.subtitle)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Open Yum Chase to create recents")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var header: some View {
        Label("Quick Log", systemImage: "sparkles")
            .foregroundStyle(.orange)
            .font(.headline)
            .lineLimit(1)
    }

    private var calorieLabel: some View {
        Group {
            if let caloriesRemaining = entry.caloriesRemaining {
                if caloriesRemaining >= 0 {
                    Text("\(caloriesRemaining.formatted()) cal left")
                } else {
                    Text("\((-caloriesRemaining).formatted()) cal over")
                }
            } else {
                Text("Goal not set")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var emptyState: some View {
        Text("Open Yum Chase to build your recent suggestions.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func quickLogButton(_ selection: QuickLogSelection, compact: Bool) -> some View {
        let isPending = entry.pendingSelectionID == selection.id
        let isComplete = entry.receipt?.selectionID == selection.id
        return Button(intent: LogRecentItemIntent(item: QuickLogSelectionEntity(selection: selection))) {
            HStack(spacing: 8) {
                Group {
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: isComplete ? "checkmark.circle.fill" : "plus.circle.fill")
                            .foregroundStyle(isComplete ? .green : .orange)
                            .symbolEffect(.bounce, value: isComplete)
                    }
                }
                .frame(width: compact ? 14 : 20, height: compact ? 14 : 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.title)
                        .font(compact ? .caption.weight(.semibold) : .headline)
                        .lineLimit(compact ? 1 : 2)
                    Text(selection.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .disabled(isPending)
        .buttonStyle(.plain)
    }
}

struct VitaChaseQuickLogWidget: Widget {
    let kind = SharedDiaryStorage.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickLogWidgetProvider()) { entry in
            QuickLogWidgetView(entry: entry)
        }
        .configurationDisplayName("Yum Chase Quick Log")
        .description("Log a Magic or recent food and check today’s calories left.")
        .supportedFamilies([
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct CaloriesLeftWidgetEntry: TimelineEntry {
    let date: Date
    let summary: CaloriesLeftWidgetSummary?
}

struct CaloriesLeftWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesLeftWidgetEntry {
        CaloriesLeftWidgetEntry(
            date: Date(),
            summary: CaloriesLeftWidgetSummary(
                progress: DailyCalorieProgress(calories: 760, goal: 2_000),
                carbs: 82,
                fat: 24,
                protein: 61,
                foods: [
                    CaloriesLeftWidgetFood(id: UUID(), name: "Cappuccino", amount: "1 serving", calories: 120),
                    CaloriesLeftWidgetFood(id: UUID(), name: "Avocado toast", amount: "1 slice", calories: 340)
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesLeftWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CaloriesLeftWidgetEntry>) -> Void
    ) {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(24 * 60 * 60)
        completion(Timeline(entries: [entry(at: now)], policy: .after(tomorrow)))
    }

    private func entry(at date: Date) -> CaloriesLeftWidgetEntry {
        guard let snapshot = try? QuickLogRepository().snapshot() else {
            return CaloriesLeftWidgetEntry(date: date, summary: nil)
        }
        return CaloriesLeftWidgetEntry(
            date: date,
            summary: snapshot.caloriesLeftWidgetSummary(at: date)
        )
    }
}

struct CaloriesLeftWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesLeftWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularContent
            case .accessoryInline:
                Label(summaryText, systemImage: "flame.fill")
                    .containerBackground(.clear, for: .widget)
            case .accessoryRectangular:
                rectangularContent
            case .systemLarge:
                largeContent
            case .systemMedium:
                mediumContent
            default:
                smallContent
            }
        }
        .widgetURL(VitaChaseDeepLink.logFoodURL)
    }

    private var smallContent: some View {
        Group {
            if let summary = entry.summary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 4) {
                        calorieFigure(summary, compact: true)
                        Spacer(minLength: 0)
                        progressIcon(summary, size: 38)
                    }
                    macroBar(summary, height: 7)
                    HStack(spacing: 4) {
                        macroValue("Carbs", summary.carbs, color: macroCarbs, compact: true)
                        macroValue("Fat", summary.fat, color: macroFat, compact: true)
                        macroValue("Protein", summary.protein, color: macroProtein, compact: true)
                    }
                }
                .padding(12)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
            } else {
                unavailableContent
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .containerBackground(.background, for: .widget)
    }

    private var mediumContent: some View {
        Group {
            if let summary = entry.summary {
                VStack(alignment: .leading, spacing: 8) {
                    summarySection(summary, compact: true)
                }
                .padding(16)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
            } else {
                unavailableContent
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .containerBackground(.background, for: .widget)
    }

    private var largeContent: some View {
        Group {
            if let summary = entry.summary {
                VStack(alignment: .leading, spacing: 11) {
                    summarySection(summary, compact: false)
                    Divider()
                    Text("Today’s food")
                        .font(.headline)
                    foodList(summary.foods, limit: 6)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 21)
                .padding(.bottom, 16)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
            } else {
                unavailableContent
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .containerBackground(.background, for: .widget)
    }

    private func summarySection(_ summary: CaloriesLeftWidgetSummary, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(alignment: .center, spacing: 12) {
                calorieFigure(summary, compact: compact)
                Spacer(minLength: 0)
                progressIcon(summary, size: compact ? 54 : 58, showsDetails: true)
            }
            macroBar(summary, height: compact ? 10 : 9)
            HStack(spacing: compact ? 8 : 12) {
                macroValue("Carbs", summary.carbs, color: macroCarbs, compact: compact, larger: compact)
                macroValue("Fat", summary.fat, color: macroFat, compact: compact, larger: compact)
                macroValue("Protein", summary.protein, color: macroProtein, compact: compact, larger: compact)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func calorieFigure(_ summary: CaloriesLeftWidgetSummary, compact: Bool) -> some View {
        let progress = summary.progress
        let value: Int
        let status: String
        let color: Color
        if let over = progress.over, over > 0 {
            value = over
            status = "calories over"
            color = coral
        } else if let remaining = progress.remaining {
            value = remaining
            status = "calories left"
            color = .primary
        } else {
            value = progress.consumed
            status = "calories"
            color = .primary
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted())
                .font(.system(size: compact ? 33 : 44, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .monospacedDigit()
            Text(status)
                .font(compact ? .caption2.weight(.medium) : .subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.accessibilityLabel)
    }

    private func progressIcon(
        _ summary: CaloriesLeftWidgetSummary,
        size: CGFloat,
        showsDetails: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(coral.opacity(0.12))
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(coral)
                Circle().stroke(coral.opacity(0.2), lineWidth: 3)
                if let fraction = summary.progress.fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(coral, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: size, height: size)
            if showsDetails {
                if let goal = summary.progress.goal {
                    Text("\(summary.progress.consumed.formatted()) / \(goal.formatted()) cal")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                } else {
                    Text("Goal not set")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func macroBar(_ summary: CaloriesLeftWidgetSummary, height: CGFloat) -> some View {
        let carbs = max(summary.carbs, 0)
        let fat = max(summary.fat, 0)
        let protein = max(summary.protein, 0)
        let total = carbs + fat + protein
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if total > 0 {
                    HStack(spacing: 0) {
                        Rectangle().fill(macroCarbs).frame(width: geometry.size.width * CGFloat(carbs / total))
                        Rectangle().fill(macroFat).frame(width: geometry.size.width * CGFloat(fat / total))
                        Rectangle().fill(macroProtein).frame(width: geometry.size.width * CGFloat(protein / total))
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carbs \(summary.carbs.cleanAmount) grams, fat \(summary.fat.cleanAmount) grams, protein \(summary.protein.cleanAmount) grams")
    }

    private func macroValue(
        _ title: String,
        _ value: Double,
        color: Color,
        compact: Bool,
        larger: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
            Text(compact && title.count > 1 ? String(title.prefix(1)) : title)
                .foregroundStyle(.secondary)
            Text("\(value.cleanAmount)g")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(compact && !larger ? .caption2 : .caption)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.cleanAmount) grams")
    }

    @ViewBuilder
    private func foodList(_ foods: [CaloriesLeftWidgetFood], limit: Int) -> some View {
        if foods.isEmpty {
            Text("No food logged today")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(foods.prefix(limit)) { food in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(food.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(food.amount)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("\(food.calories.formatted()) cal")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Today’s calories", systemImage: "flame.fill")
                .font(.headline)
            Text("Open Yum Chase on your iPhone to refresh the diary.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var circularContent: some View {
        Group {
            if let summary = entry.summary {
                CaloriesProgressRing(
                    progress: summary.progress.fraction ?? 0,
                    value: compactValue(summary),
                    status: compactStatus(summary),
                    size: 44
                )
            } else {
                Image(systemName: "flame.fill").foregroundStyle(coral)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Calories left", systemImage: "flame.fill")
                .font(.caption)
            Text(summaryText)
                .font(.title3.bold())
                .lineLimit(1)
            if let fraction = entry.summary?.progress.fraction {
                ProgressView(value: fraction).tint(coral)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private func compactValue(_ summary: CaloriesLeftWidgetSummary) -> String {
        let progress = summary.progress
        let value = (progress.over ?? 0) > 0 ? (progress.over ?? 0) : (progress.remaining ?? progress.consumed)
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return value.formatted()
    }

    private func compactStatus(_ summary: CaloriesLeftWidgetSummary) -> String {
        if (summary.progress.over ?? 0) > 0 { return "over" }
        return summary.progress.goal == nil ? "cal" : "left"
    }

    private var summaryText: String {
        guard let summary = entry.summary else { return "Diary unavailable" }
        if let over = summary.progress.over, over > 0 {
            return "\(over.formatted()) over"
        }
        if let remaining = summary.progress.remaining {
            return "\(remaining.formatted()) left"
        }
        return "\(summary.progress.consumed.formatted()) cal"
    }

    private var cardColor: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }

    private var coral: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 0.39, blue: 0.33, alpha: 1)
                : UIColor(red: 0.94, green: 0.35, blue: 0.28, alpha: 1)
        })
    }

    private let macroCarbs = Color(uiColor: .systemBlue)
    private let macroFat = Color(uiColor: .systemPurple)
    private let macroProtein = Color(uiColor: .systemGreen)
}

private struct CaloriesProgressRing: View {
    let progress: Double
    let value: String
    let status: String
    let size: CGFloat

    private let baseLineWidth: CGFloat = 4
    private let progressColor = Color(red: 0.94, green: 0.35, blue: 0.28).opacity(0.9)

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.22), lineWidth: baseLineWidth)

            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(progressColor, style: StrokeStyle(lineWidth: baseLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(progressColor, style: StrokeStyle(lineWidth: baseLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(progressColor)
                    .frame(width: baseLineWidth * 2.1, height: baseLineWidth * 2.1)
                    // The arc's centerline is at the outer radius of the Circle
                    // shape. Keep the marker on that same radius instead of
                    // shifting it inward by half the stroke width.
                    .offset(y: -(size / 2))
                    .rotationEffect(.degrees(min(progress - 1, 1) * 360))
            }

            VStack(spacing: -1) {
                Text(value)
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .monospacedDigit()
                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: size * 0.15, weight: .medium, design: .rounded))
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(value)
    }
}

struct VitaChaseCaloriesLeftWidget: Widget {
    let kind = SharedDiaryStorage.caloriesWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaloriesLeftWidgetProvider()) { entry in
            CaloriesLeftWidgetView(entry: entry)
        }
        .configurationDisplayName("Yum Chase Calories Left")
        .description("See today’s calories and macros, plus logged foods in larger sizes.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

@main
struct VitaChaseWidgetBundle: WidgetBundle {
    var body: some Widget {
        VitaChaseQuickLogWidget()
        VitaChaseCaloriesLeftWidget()
    }
}
