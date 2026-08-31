import AppIntents
import SwiftUI
import WidgetKit

struct QuickLogWidgetEntry: TimelineEntry {
    let date: Date
    let selections: [QuickLogSelection]
    let caloriesRemaining: Int?
    let receipt: QuickLogReceipt?
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
            receipt: nil
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
                receipt: recentReceipt(at: date)
            )
        }
        return QuickLogWidgetEntry(
            date: date,
            selections: snapshot.widgetSelections(at: date, limit: 8),
            caloriesRemaining: try? snapshot.caloriesRemaining(at: date),
            receipt: recentReceipt(at: date)
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
            case .systemSmall:
                smallContent
            case .systemLarge:
                largeContent
            default:
                mediumContent
            }
        }
        .widgetURL(VitaChaseDeepLink.logFoodURL)
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let selection = entry.selections.first {
                quickLogButton(selection, compact: false)
            } else {
                emptyState
            }
            Spacer(minLength: 0)
            calorieLabel
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                header
                Spacer()
                calorieLabel
            }
            if entry.selections.isEmpty {
                emptyState
            } else {
                ForEach(entry.selections.prefix(3)) { selection in
                    quickLogButton(selection, compact: true)
                }
            }
        }
        .padding()
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
                    ForEach(entry.selections.prefix(8)) { selection in
                        quickLogButton(selection, compact: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
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
        .accessibilityLabel("Open Log Food in VitaChase")
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
                Text("Open VitaChase to create recents")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var header: some View {
        Group {
            if let receipt = entry.receipt {
                Label("Logged \(receipt.title)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Quick Log", systemImage: "sparkles")
                    .foregroundStyle(.orange)
            }
        }
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
        Text("Open VitaChase to build your recent suggestions.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func quickLogButton(_ selection: QuickLogSelection, compact: Bool) -> some View {
        Button(intent: LogRecentItemIntent(item: QuickLogSelectionEntity(selection: selection))) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.title)
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(compact ? 1 : 2)
                    Text(selection.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct VitaChaseQuickLogWidget: Widget {
    let kind = SharedDiaryStorage.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickLogWidgetProvider()) { entry in
            QuickLogWidgetView(entry: entry)
        }
        .configurationDisplayName("VitaChase Quick Log")
        .description("Log a Magic or recent food and check today’s calories left.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct CaloriesLeftWidgetEntry: TimelineEntry {
    let date: Date
    let goal: Int?
    let remaining: Int?
}

struct CaloriesLeftWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesLeftWidgetEntry {
        CaloriesLeftWidgetEntry(date: Date(), goal: 2_000, remaining: 740)
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
            return CaloriesLeftWidgetEntry(date: date, goal: nil, remaining: nil)
        }
        return CaloriesLeftWidgetEntry(
            date: date,
            goal: snapshot.document.dailyCalorieGoal,
            remaining: try? snapshot.caloriesRemaining(at: date)
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
                Label(summary, systemImage: "flame.fill")
                    .containerBackground(.clear, for: .widget)
            case .accessoryRectangular:
                rectangularContent
            case .systemMedium:
                mediumContent
            default:
                smallContent
            }
        }
        .widgetURL(VitaChaseDeepLink.logFoodURL)
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calories Left", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(displayValue)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                Text(displayStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.orange)
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }

    private var mediumContent: some View {
        HStack(spacing: 18) {
            CaloriesProgressRing(
                progress: ringProgress,
                value: compactValue,
                status: compactStatus,
                size: 82
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Calories Left Today")
                    .font(.headline)
                Text(summary)
                    .font(.title2.bold())
                if let goal = entry.goal {
                    Text("Daily goal: \(goal.formatted()) cal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }

    private var circularContent: some View {
        CaloriesProgressRing(
            progress: ringProgress,
            value: compactValue,
            status: compactStatus,
            size: 44
        )
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Calories left", systemImage: "flame.fill")
                .font(.caption)
            Text(summary)
                .font(.title3.bold())
                .lineLimit(1)
            ProgressView(value: progress)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var progress: Double {
        guard let goal = entry.goal, goal > 0, let remaining = entry.remaining else { return 0 }
        return min(max(Double(goal - remaining) / Double(goal), 0), 1)
    }

    private var ringProgress: Double {
        guard let goal = entry.goal, goal > 0, let remaining = entry.remaining else { return 0 }
        return min(max(Double(goal - remaining) / Double(goal), 0), 2)
    }

    private var displayValue: String {
        guard let remaining = entry.remaining else { return "—" }
        return abs(remaining).formatted()
    }

    private var displayStatus: String {
        guard let remaining = entry.remaining else { return "Set a goal in VitaChase" }
        return remaining >= 0 ? "calories left" : "calories over"
    }

    private var compactValue: String {
        guard let remaining = entry.remaining else { return "—" }
        let value = abs(remaining)
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return value.formatted()
    }

    private var compactStatus: String {
        guard let remaining = entry.remaining else { return "" }
        return remaining >= 0 ? "left" : "over"
    }

    private var summary: String {
        guard let remaining = entry.remaining else { return "Goal not set" }
        return remaining >= 0
            ? "\(remaining.formatted()) calories left"
            : "\((-remaining).formatted()) calories over"
    }
}

private struct CaloriesProgressRing: View {
    let progress: Double
    let value: String
    let status: String
    let size: CGFloat

    private let baseLineWidth: CGFloat = 4
    private let progressColor = Color.orange.opacity(0.88)

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
        .configurationDisplayName("VitaChase Calories Left")
        .description("See how many calories remain against today’s goal.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
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
