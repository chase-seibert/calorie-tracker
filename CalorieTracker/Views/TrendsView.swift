import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var range = 30

    private var points: [TrendPoint] {
        diary.totalsByDay(numberOfDays: range).map {
            TrendPoint(date: $0.date, nutrients: $0.nutrients, status: diary.status(on: $0.date)?.kind)
        }
    }

    private var visibleStatuses: [DayStatusKind] {
        DayStatusKind.allCases.filter { status in points.contains { $0.status == status } }
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Picker("Range", selection: $range) {
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)

                    chartCard(title: "Calories", color: AppTheme.coral, value: { $0.nutrients.calories })
                    macroChart
                }
                .padding(16)
            }
        }
        .navigationTitle("Trends")
    }

    private func chartCard(title: String, color: Color, value: @escaping (TrendPoint) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.bold))
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, value(point))
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value(title, value(point))
                    )
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                    if let status = point.status {
                        RuleMark(x: .value("Special day", point.date))
                            .foregroundStyle(statusColor(status).opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 6))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 220)
            specialDayLegend
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var macroChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macros").font(.title3.weight(.bold))
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Grams", point.nutrients.carbs), series: .value("Macro", "Carbs"))
                        .foregroundStyle(by: .value("Macro", "Carbs"))
                    LineMark(x: .value("Date", point.date), y: .value("Grams", point.nutrients.fat), series: .value("Macro", "Fat"))
                        .foregroundStyle(by: .value("Macro", "Fat"))
                    LineMark(x: .value("Date", point.date), y: .value("Grams", point.nutrients.protein), series: .value("Macro", "Protein"))
                        .foregroundStyle(by: .value("Macro", "Protein"))
                    if let status = point.status {
                        RuleMark(x: .value("Special day", point.date))
                            .foregroundStyle(statusColor(status).opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 6))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Carbs": AppTheme.carbs,
                "Fat": AppTheme.fat,
                "Protein": AppTheme.protein,
            ])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 240)
            specialDayLegend
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var specialDayLegend: some View {
        if !visibleStatuses.isEmpty {
            HStack(spacing: 14) {
                ForEach(visibleStatuses, id: \.self) { status in
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(statusColor(status))
                            .frame(width: 6, height: 18)
                        Text(status.title)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func statusColor(_ status: DayStatusKind) -> Color {
        switch status {
        case .gap: AppTheme.gapDay
        case .cheat: AppTheme.cheatDay
        }
    }
}

private struct TrendPoint: Identifiable {
    let date: Date
    let nutrients: MacroNutrients
    let status: DayStatusKind?
    var id: Date { date }
}
