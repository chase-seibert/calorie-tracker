import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @AppStorage("trends.focus.alcohol") private var tracksAlcohol = true
    @AppStorage("trends.focus.fiber") private var tracksFiber = true
    @AppStorage("trends.focus.processedMeat") private var tracksProcessedMeat = true
    @AppStorage("trends.focus.redMeat") private var tracksRedMeat = true
    @State private var selectedMeatWeek: WeeklyMeatServings?
    @State private var classificationReviewCount = 0

    private let trendDays = 30
    private let fiberGramsPerThousandCalories = 14.0
    private let recommendedAlcoholDrinksPerDay = 2.0
    private let recommendedRedMeatServingsPerWeek = 3.0
    private let recommendedProcessedMeatServingsPerWeek = 0.0

    private var points: [TrendPoint] {
        diary.totalsByDay(numberOfDays: trendDays).map { total in
            let alcohol = diary.alcoholEntry(on: total.date)
            return TrendPoint(
                date: total.date,
                nutrients: total.nutrients,
                calories: diary.caloriesExcludingAlcohol(on: total.date),
                alcoholDrinks: alcohol?.drinks ?? 0,
                status: diary.status(on: total.date)?.kind
            )
        }
    }

    private var trendDateRange: ClosedRange<Date> {
        guard let firstDate = points.first?.date, let lastDate = points.last?.date else {
            let today = Calendar.current.startOfDay(for: Date())
            return today...today
        }
        return firstDate...lastDate
    }

    private var cheatDayCount: Int { points.count { $0.status == .cheat } }

    private var gapDayCount: Int { points.count { $0.status == .gap } }

    private var weeklyMeatPoints: [WeeklyMeatServings] {
        diary.weeklyMeatServings(numberOfDays: trendDays)
    }

    private var maximumMeatServings: Double {
        max(
            recommendedRedMeatServingsPerWeek,
            weeklyMeatPoints.flatMap { [$0.processedMeatServings, $0.redMeatServings] }.max() ?? 0
        ).rounded(.up)
    }

    private var recommendedFiberGrams: Double {
        let calorieBaseline = diary.dailyCalorieGoal ?? 2_000
        return Double(calorieBaseline) / 1_000 * fiberGramsPerThousandCalories
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    statusCounts
                    calorieChart
                    if tracksAlcohol {
                        alcoholChart
                    }
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
        .task(id: diary.hasLoadedSnapshot) {
            await loadClassificationReviewCount()
        }
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
                Text("Meat servings per week").font(.title3.weight(.bold))
                Text("Servings per week")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Text("Red meat reference: up to 3 servings; processed meat: very little, if any.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Chart {
                ForEach(weeklyMeatPoints) { point in
                    if tracksProcessedMeat {
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value("Servings", point.processedMeatServings)
                        )
                        .position(by: .value("Meat type", "Processed meat"))
                        .foregroundStyle(AppTheme.processedMeat)
                        .accessibilityLabel("Processed meat, week of \(point.weekStart.formatted(date: .abbreviated, time: .omitted))")
                        .accessibilityValue("\(point.processedMeatServings.cleanAmount) servings")
                    }

                    if tracksRedMeat {
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value("Servings", point.redMeatServings)
                        )
                        .position(by: .value("Meat type", "Red meat"))
                        .foregroundStyle(AppTheme.redMeat)
                        .accessibilityLabel("Red meat, week of \(point.weekStart.formatted(date: .abbreviated, time: .omitted))")
                        .accessibilityValue("\(point.redMeatServings.cleanAmount) servings")
                    }
                }
                if tracksProcessedMeat {
                    RuleMark(y: .value("Processed meat target", recommendedProcessedMeatServingsPerWeek))
                        .foregroundStyle(AppTheme.processedMeat.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                if tracksRedMeat {
                    RuleMark(y: .value("Red meat maximum", recommendedRedMeatServingsPerWeek))
                        .foregroundStyle(AppTheme.redMeat.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartXScale(domain: trendDateRange)
            .chartYScale(domain: 0...maximumMeatServings)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
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
            if classificationReviewCount > 0 {
                NavigationLink("Review Classifications") { ReviewClassificationsView() }
                    .font(.caption)
            }
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
                  guard let left = proxy.position(forX: $0.weekStart),
                        let right = proxy.position(forX: $1.weekStart)
                  else {
                      return abs($0.weekStart.timeIntervalSince(selectedDate))
                          < abs($1.weekStart.timeIntervalSince(selectedDate))
                  }
                  return abs(left - xPosition) < abs(right - xPosition)
              })
        else { return }
        selectedMeatWeek = week
    }

    private func meatDays(in week: WeeklyMeatServings) -> [MeatDayFoods] {
        diary.meatDayFoods(numberOfDays: trendDays).filter {
            $0.date >= week.weekStart
                && $0.date <= week.weekEnd
                && ((tracksProcessedMeat && !$0.processedMeatFoods.isEmpty)
                    || (tracksRedMeat && !$0.redMeatFoods.isEmpty))
        }
    }

    private var calorieChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calories")
                    .font(.title3.weight(.bold))
                Text(diary.dailyCalorieGoal.map { "Target: \($0.formatted()) calories" } ?? "Target: Not set")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Calories", point.calories)
                    )
                    .foregroundStyle(AppTheme.coral)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Calories", point.calories)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.coral.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                if let goal = diary.dailyCalorieGoal {
                    RuleMark(y: .value("Daily calorie target", goal))
                        .foregroundStyle(AppTheme.coral.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }
            .chartXScale(domain: trendDateRange)
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

    private var alcoholChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Alcohol")
                    .font(.title3.weight(.bold))
                Text("Daily drinks · no more than 2 drinks in one day")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Chart {
                ForEach(points) { point in
                    if point.alcoholDrinks > 0 {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Drinks", point.alcoholDrinks)
                        )
                        .foregroundStyle(AppTheme.coral)
                        .accessibilityLabel(point.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue("\(point.alcoholDrinks) drink\(point.alcoholDrinks == 1 ? "" : "s")")
                    }
                }
                RuleMark(y: .value("Daily drinks guidance", recommendedAlcoholDrinksPerDay))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            .chartXScale(domain: trendDateRange)
            .chartYScale(domain: 0...Double(max(3, maximumAlcoholDrinks)))
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 190)
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var maximumAlcoholDrinks: Int {
        max(points.map(\.alcoholDrinks).max() ?? 0, 1)
    }

    private func loadClassificationReviewCount() async {
        guard diary.hasLoadedSnapshot else { return }
        do {
            classificationReviewCount = try await diary.foodResolutionReview().count
        } catch {
            classificationReviewCount = 0
        }
    }

    private var macroChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Macros").font(.title3.weight(.bold))
                Text("Stacked daily grams")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            Chart {
                ForEach(points) { point in
                    let carbs = max(point.nutrients.carbs, 0)
                    let fat = max(point.nutrients.fat, 0)
                    let protein = max(point.nutrients.protein, 0)
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Baseline", 0.0),
                        yEnd: .value("Grams", protein)
                    )
                        .foregroundStyle(by: .value("Macro", "Protein"))
                        .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Grams", protein),
                        yEnd: .value("Grams", protein + fat)
                    )
                        .foregroundStyle(by: .value("Macro", "Fat"))
                        .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Grams", protein + fat),
                        yEnd: .value("Grams", protein + fat + carbs)
                    )
                        .foregroundStyle(by: .value("Macro", "Carbs"))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartXScale(domain: trendDateRange)
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
            .chartLegend(position: .bottom, spacing: 16)
            .frame(height: 260)
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var fiberChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fiber")
                    .font(.title3.weight(.bold))
                Text("Daily recommendation: \(recommendedFiberGrams.cleanAmount) g")
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
                RuleMark(y: .value("Daily fiber recommendation", recommendedFiberGrams))
                    .foregroundStyle(AppTheme.fiber.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .chartXScale(domain: trendDateRange)
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

    let week: WeeklyMeatServings
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

private struct TrendPoint: Identifiable {
    let date: Date
    let nutrients: MacroNutrients
    let calories: Double
    let alcoholDrinks: Int
    let status: DayStatusKind?
    var id: Date { date }
}
