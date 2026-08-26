import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    @AppStorage("trends.focus.fiber") private var tracksFiber = true
    @AppStorage("trends.focus.processedMeat") private var tracksProcessedMeat = true
    @AppStorage("trends.focus.redMeat") private var tracksRedMeat = true
    @State private var selectedMeatWeek: WeeklyMeatDays?

    private let trendDays = 30

    private var points: [TrendPoint] {
        diary.totalsByDay(numberOfDays: trendDays).map {
            TrendPoint(
                date: $0.date,
                nutrients: $0.nutrients,
                alcoholDrinks: diary.alcoholDrinkCount(on: $0.date),
                status: diary.status(on: $0.date)?.kind
            )
        }
    }

    private var cheatDayCount: Int { points.count { $0.status == .cheat } }

    private var gapDayCount: Int { points.count { $0.status == .gap } }

    private var weeklyMeatPoints: [WeeklyMeatDays] {
        diary.weeklyMeatDays(numberOfDays: trendDays)
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    statusCounts
                    calorieAndAlcoholChart
                    if tracksFiber {
                        fiberChart
                    }
                    if tracksProcessedMeat || tracksRedMeat {
                        meatDaysChart
                    }
                    macroChart
                }
                .padding(16)
            }
        }
        .navigationTitle("Last 30 Days")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Toggle("Alcohol", isOn: $tracksAlcohol)
                    Toggle("Fiber", isOn: $tracksFiber)
                    Toggle("Processed Meat", isOn: $tracksProcessedMeat)
                    Toggle("Red Meat", isOn: $tracksRedMeat)
                } label: {
                    Label("Trend Focus Areas", systemImage: "slider.horizontal.3")
                }

                NavigationLink {
                    FoodWeightReportView()
                } label: {
                    Label("Food Weight Report", systemImage: "doc.text")
                }
            }
        }
        .sheet(item: $selectedMeatWeek) { week in
            MeatWeekFoodsView(
                week: week,
                days: meatDays(in: week),
                showsProcessedMeat: tracksProcessedMeat,
                showsRedMeat: tracksRedMeat
            )
            .presentationDetents([.medium, .large])
        }
        .analyticsScreen("trends")
    }

    private var statusCounts: some View {
        HStack(spacing: 10) {
            statusCount(
                cheatDayCount,
                title: "Cheat days",
                color: AppTheme.cheatDay
            )
            statusCount(
                gapDayCount,
                title: "Gap days",
                color: AppTheme.gapDay
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusCount(_ count: Int, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(count.formatted())
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(count)")
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
                    if tracksProcessedMeat {
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value("Days", point.processedMeatDays)
                        )
                        .position(by: .value("Meat type", "Processed meat"))
                        .foregroundStyle(AppTheme.processedMeat)
                        .accessibilityLabel("Processed meat, week of \(point.weekStart.formatted(date: .abbreviated, time: .omitted))")
                        .accessibilityValue("\(point.processedMeatDays) days")
                    }

                    if tracksRedMeat {
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
            }
            .chartYScale(domain: 0...7)
            .chartYAxis {
                AxisMarks(values: [0, 1, 2, 3, 4, 5, 6, 7])
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
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
                if tracksProcessedMeat {
                    meatLegend(icon: "🥓", title: "Processed meat", color: AppTheme.processedMeat)
                }
                if tracksRedMeat {
                    meatLegend(icon: "🥩", title: "Red meat", color: AppTheme.redMeat)
                }
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
        diary.meatDayFoods(numberOfDays: trendDays).filter {
            $0.date >= week.weekStart
                && $0.date <= week.weekEnd
                && ((tracksProcessedMeat && !$0.processedMeatFoods.isEmpty)
                    || (tracksRedMeat && !$0.redMeatFoods.isEmpty))
        }
    }

    private var calorieAndAlcoholChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tracksAlcohol ? "Calories & drinks" : "Calories")
                    .font(.title3.weight(.bold))
                if tracksAlcohol {
                    Text("Each wine glass is one drink")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
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
                    if tracksAlcohol, point.alcoholDrinks > 0 {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Drink stack baseline", 0)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 3) {
                            AlcoholTrendStack(drinks: point.alcoholDrinks)
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
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var fiberChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fiber")
                    .font(.title3.weight(.bold))
                Text("Daily grams")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Chart {
                ForEach(points) { point in
                    if let fiber = point.nutrients.fiber {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Fiber", fiber)
                        )
                        .foregroundStyle(AppTheme.fiber)
                        .accessibilityLabel(point.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(fiber.cleanAmount) grams of fiber")
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 210)
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

}

private struct MeatWeekFoodsView: View {
    @Environment(\.dismiss) private var dismiss

    let week: WeeklyMeatDays
    let days: [MeatDayFoods]
    let showsProcessedMeat: Bool
    let showsRedMeat: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                Group {
                    if days.isEmpty {
                        ContentUnavailableView(
                            "No focused foods",
                            systemImage: "fork.knife",
                            description: Text("No foods matching your selected focus areas were logged during this week.")
                        )
                    } else {
                        List(days) { day in
                            Section(day.date.formatted(date: .complete, time: .omitted)) {
                                if showsProcessedMeat, !day.processedMeatFoods.isEmpty {
                                    meatFoodGroup(
                                        icon: "🥓",
                                        title: "Processed meat",
                                        foods: day.processedMeatFoods,
                                        color: AppTheme.processedMeat
                                    )
                                }
                                if showsRedMeat, !day.redMeatFoods.isEmpty {
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
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Focus foods")
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

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<drinks, id: \.self) { _ in
                Image(systemName: "wineglass.fill")
                    .font(.system(size: 14, weight: .semibold))
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
