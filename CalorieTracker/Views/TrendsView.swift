import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var range = 30
    @State private var selectedMeatWeek: WeeklyMeatDays?

    private var points: [TrendPoint] {
        diary.totalsByDay(numberOfDays: range).map {
            TrendPoint(
                date: $0.date,
                nutrients: $0.nutrients,
                alcoholDrinks: diary.alcoholDrinkCount(on: $0.date),
                status: diary.status(on: $0.date)?.kind
            )
        }
    }

    private var visibleStatuses: [DayStatusKind] {
        DayStatusKind.allCases.filter { status in points.contains { $0.status == status } }
    }

    private var weeklyMeatPoints: [WeeklyMeatDays] {
        diary.weeklyMeatDays(numberOfDays: range)
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

                    calorieAndAlcoholChart
                    meatDaysChart
                    macroChart
                }
                .padding(16)
            }
        }
        .navigationTitle("Trends")
        .sheet(item: $selectedMeatWeek) { week in
            MeatWeekFoodsView(
                week: week,
                days: meatDays(in: week)
            )
            .presentationDetents([.medium, .large])
        }
        .analyticsScreen("trends")
        .onChange(of: range) { _, newRange in
            AppAnalytics.capture(
                "trends.range_changed",
                properties: ["days": String(newRange)]
            )
        }
    }

    private var meatDaysChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meat days per week").font(.title3.weight(.bold))
                Text("A day counts once per category, regardless of quantity")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Chart {
                ForEach(weeklyMeatPoints) { point in
                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Days", point.processedMeatDays)
                    )
                    .position(by: .value("Meat type", "Processed meat"))
                    .foregroundStyle(AppTheme.processedMeat)
                    .accessibilityLabel("Processed meat, week of \(point.weekStart.formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityValue("\(point.processedMeatDays) days")

                    BarMark(
                        x: .value("Week", point.weekStart, unit: .weekOfYear),
                        y: .value("Days", point.redMeatDays)
                    )
                    .position(by: .value("Meat type", "Red meat"))
                    .foregroundStyle(AppTheme.redMeat)
                    .accessibilityLabel("Red meat, week of \(point.weekStart.formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityValue("\(point.redMeatDays) days")
                }
            }
            .chartYScale(domain: 0...7)
            .chartYAxis {
                AxisMarks(values: [0, 1, 2, 3, 4, 5, 6, 7])
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: range == 90 ? 5 : 4)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                selectMeatWeek(
                                    at: value.location,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            }
                        )
                }
            }
            .frame(height: 190)

            HStack(spacing: 18) {
                meatLegend(icon: "🥓", title: "Processed meat", color: AppTheme.processedMeat)
                meatLegend(icon: "🥩", title: "Red meat", color: AppTheme.redMeat)
            }
            .accessibilityElement(children: .combine)

            Text("Tap a week to see the foods included")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func meatLegend(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.body)
                .grayscale(0.15)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private func selectMeatWeek(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotRect = geometry[plotFrame]
        let xPosition = location.x - plotRect.origin.x
        guard xPosition >= 0,
              xPosition <= plotRect.width,
              let selectedDate: Date = proxy.value(atX: xPosition),
              let week = weeklyMeatPoints.min(by: {
                  abs($0.weekStart.timeIntervalSince(selectedDate))
                      < abs($1.weekStart.timeIntervalSince(selectedDate))
              })
        else { return }
        selectedMeatWeek = week
    }

    private func meatDays(in week: WeeklyMeatDays) -> [MeatDayFoods] {
        diary.meatDayFoods(numberOfDays: range).filter {
            $0.date >= week.weekStart && $0.date <= week.weekEnd
        }
    }

    private var calorieAndAlcoholChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calories & drinks").font(.title3.weight(.bold))
                Text("Each wine glass is one drink")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Calories", point.nutrients.calories)
                    )
                    .foregroundStyle(AppTheme.coral)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Calories", point.nutrients.calories)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.coral.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    if let status = point.status {
                        RuleMark(x: .value("Special day", point.date))
                            .foregroundStyle(statusColor(status).opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 6))
                    }
                    if point.alcoholDrinks > 0 {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Drink stack baseline", 0)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 3) {
                            AlcoholTrendStack(drinks: point.alcoholDrinks, range: range)
                        }
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

private struct MeatWeekFoodsView: View {
    @Environment(\.dismiss) private var dismiss

    let week: WeeklyMeatDays
    let days: [MeatDayFoods]

    var body: some View {
        NavigationStack {
            Group {
                if days.isEmpty {
                    ContentUnavailableView(
                        "No meat foods",
                        systemImage: "fork.knife",
                        description: Text("No qualifying foods were logged during this week.")
                    )
                } else {
                    List(days) { day in
                        Section(day.date.formatted(date: .complete, time: .omitted)) {
                            if !day.processedMeatFoods.isEmpty {
                                meatFoodGroup(
                                    icon: "🥓",
                                    title: "Processed meat",
                                    foods: day.processedMeatFoods,
                                    color: AppTheme.processedMeat
                                )
                            }
                            if !day.redMeatFoods.isEmpty {
                                meatFoodGroup(
                                    icon: "🥩",
                                    title: "Red meat",
                                    foods: day.redMeatFoods,
                                    color: AppTheme.redMeat
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Meat foods")
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(weekRangeTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func meatFoodGroup(
        icon: String,
        title: String,
        foods: [String],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(icon)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.headline)
            }
            ForEach(foods, id: \.self) { food in
                Text(food)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var weekRangeTitle: String {
        "\(week.weekStart.formatted(date: .abbreviated, time: .omitted))–\(week.weekEnd.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct AlcoholTrendStack: View {
    let drinks: Int
    let range: Int

    private var iconSize: CGFloat {
        switch range {
        case 0...14: 16
        case 15...30: 14
        default: 10
        }
    }

    private var iconSpacing: CGFloat {
        switch range {
        case 0...14: 3
        case 15...30: 2
        default: 1
        }
    }

    var body: some View {
        VStack(spacing: iconSpacing) {
            ForEach(0..<drinks, id: \.self) { _ in
                Image(systemName: "wineglass.fill")
                    .font(.system(size: iconSize, weight: .semibold))
            }
        }
        .foregroundStyle(AppTheme.coral)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(drinks) drink\(drinks == 1 ? "" : "s")")
    }
}

private struct TrendPoint: Identifiable {
    let date: Date
    let nutrients: MacroNutrients
    let alcoholDrinks: Int
    let status: DayStatusKind?
    var id: Date { date }
}
