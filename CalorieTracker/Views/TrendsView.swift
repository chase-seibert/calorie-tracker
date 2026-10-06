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
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss

    let week: WeeklyMeatServings
    @State private var days: [MeatDayFoods]
    let showsProcessedMeat: Bool
    let showsRedMeat: Bool
    @State private var activeEditor: MeatDetailEditor?

    private enum MeatDetailEditor: Identifiable {
        case foodTags(Food)
        case loggedTags(MeatDayFood)
        case servings(MeatDayFood)

        var id: String {
            switch self {
            case let .foodTags(food): "food-tags:\(food.id)"
            case let .loggedTags(item): "logged-tags:\(item.id)"
            case let .servings(item): "servings:\(item.id)"
            }
        }
    }

    init(week: WeeklyMeatServings, days: [MeatDayFoods], showsProcessedMeat: Bool, showsRedMeat: Bool) {
        self.week = week
        _days = State(initialValue: days)
        self.showsProcessedMeat = showsProcessedMeat
        self.showsRedMeat = showsRedMeat
    }

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
                                        foods: day.processedMeatItems,
                                        color: AppTheme.processedMeat,
                                        onAdjustServings: { activeEditor = .servings($0) },
                                        onEditTags: { activeEditor = .foodTags($0) },
                                        onEditLoggedTags: { activeEditor = .loggedTags($0) }
                                    )
                                }
                                if showsRedMeat, !day.redMeatFoods.isEmpty {
                                    meatFoodGroup(
                                        icon: "🥩",
                                        title: "Red meat",
                                        foods: day.redMeatItems,
                                        color: AppTheme.redMeat,
                                        onAdjustServings: { activeEditor = .servings($0) },
                                        onEditTags: { activeEditor = .foodTags($0) },
                                        onEditLoggedTags: { activeEditor = .loggedTags($0) }
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(weekRangeTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.muted)
                    Text("Foods appear under categories whose meat tag is Yes. Weekly totals add each logged item: ounces convert to grams, then grams are divided by the portion weight (or default serving weight). Serving-unit logs count directly. Meal-level tags without a matching ingredient use the logged meal count.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $activeEditor, onDismiss: refreshDays) { editor in
                switch editor {
                case let .foodTags(food):
                    NavigationStack {
                        CorpusFoodMeatTagEditor(food: food, onSaved: refreshDays)
                            .padding()
                            .navigationTitle(food.name)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { activeEditor = nil }
                                }
                            }
                    }
                    .presentationDetents([.medium])
                case let .loggedTags(item):
                    LoggedMeatTagSelectionView(item: item)
                case let .servings(item):
                    MeatServingsAdjustmentView(item: item)
                }
            }
        }
    }

    private func meatFoodGroup(
        icon: String,
        title: String,
        foods: [MeatDayFood],
        color: Color,
        onAdjustServings: @escaping (MeatDayFood) -> Void,
        onEditTags: @escaping (Food) -> Void,
        onEditLoggedTags: @escaping (MeatDayFood) -> Void
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
            ForEach(foods) { item in
                MeatDayFoodRow(
                    item: item,
                    onAdjustServings: { onAdjustServings(item) },
                    onEditTags: {
                        guard let food = item.food, FoodCatalogIdentity(food: food) != nil else { return }
                        onEditTags(food)
                    },
                    onEditLoggedTags: { onEditLoggedTags(item) }
                )
            }
        }
        .padding(.vertical, 3)
    }

    private var weekRangeTitle: String {
        "\(week.weekStart.formatted(date: .abbreviated, time: .omitted))–\(week.weekEnd.formatted(date: .abbreviated, time: .omitted))"
    }

    private func refreshDays() {
        days = diary.meatDayFoods(numberOfDays: 30).filter {
            $0.date >= week.weekStart && $0.date <= week.weekEnd
                && ((showsProcessedMeat && !$0.processedMeatFoods.isEmpty)
                    || (showsRedMeat && !$0.redMeatFoods.isEmpty))
        }
    }
}

private struct MeatDayFoodRow: View {
    let item: MeatDayFood
    let onAdjustServings: () -> Void
    let onEditTags: () -> Void
    let onEditLoggedTags: () -> Void

    private func calculationDescription(for contribution: MeatDayFoodContribution) -> String {
        if contribution.isMealFallback {
            return "Meal-level meat tag; counted from the logged meal quantity."
        }
        guard let food = item.food else { return "Serving amount unavailable." }
        let portion = food.portion(id: contribution.portionID)
        let portionLabel = portion?.label ?? food.servingDescription ?? "serving"
        if contribution.unit == .serving {
            let grams = portion?.grams ?? food.servingGrams ?? food.baseAmountGrams
            return "Logged \(contribution.amount.cleanAmount) serving(s) of \(portionLabel) (\(grams.cleanAmount) g each) = \(contribution.calculatedServings.cleanAmount) servings."
        }
        let grams = contribution.unit.grams(for: contribution.amount, food: food, portionID: contribution.portionID)
        let servingGrams = portion?.grams ?? food.servingGrams ?? food.baseAmountGrams
        return "Logged \(contribution.amount.cleanAmount) \(contribution.unit.title) = \(grams.cleanAmount) g ÷ \(servingGrams.cleanAmount) g per \(portionLabel) = \(contribution.calculatedServings.cleanAmount) servings."
    }

    private var calculationDescription: String {
        item.contributions.map(calculationDescription(for:)).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text("\(item.servings.cleanAmount) servings")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            Text(calculationDescription)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if item.hasManualServingOverride {
                Text("Manual chart count · calculated value was \(item.calculatedServings.cleanAmount)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.coral)
            }
            HStack(spacing: 18) {
                Button("Adjust servings", systemImage: "slider.horizontal.3", action: onAdjustServings)
                    .font(.caption.weight(.medium))
                Button("Edit logged tags", systemImage: "tag", action: onEditLoggedTags)
                    .font(.caption.weight(.medium))
                if item.food.map({ FoodCatalogIdentity(food: $0) != nil }) == true {
                    Button("Edit food tags", systemImage: "tag", action: onEditTags)
                        .font(.caption.weight(.medium))
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }
}

private struct LoggedMeatTagSelectionView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss

    let item: MeatDayFood

    var body: some View {
        NavigationStack {
            List(item.contributions) { contribution in
                if let entry = diary.document.entries.first(where: { $0.id == contribution.entryID }) {
                    NavigationLink {
                        QuantityEditor(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contributionName(contribution, entry: entry))
                                .font(.body.weight(.medium))
                            Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(entry.amount.cleanAmount) \(entry.unit.title)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                }
            }
            .navigationTitle("Logged entries")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func contributionName(_ contribution: MeatDayFoodContribution, entry: DiaryEntry) -> String {
        guard let mealItemID = contribution.mealItemID,
            let ingredient = entry.mealItems?.first(where: { $0.id == mealItemID })
        else { return entry.food.name }
        return "\(entry.food.name) — \(ingredient.food.name)"
    }
}

private struct MeatServingsAdjustmentView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss

    let item: MeatDayFood
    @State private var servings: Double
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(item: MeatDayFood) {
        self.item = item
        _servings = State(initialValue: item.servings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Logged amount") {
                    Text(loggedAmountDescription)
                }
                Section("Calculation") {
                    Text(calculationDescription)
                    LabeledContent("Calculated servings", value: item.calculatedServings.cleanAmount)
                }
                Section("Counted servings") {
                    TextField("Servings", value: $servings, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                    Text("This changes the meat chart count only. It does not change the food log or nutrition.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    if item.hasManualServingOverride {
                        Button("Restore calculated count (\(item.calculatedServings.cleanAmount))") {
                            save(override: nil)
                        }
                        .disabled(isSaving)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Adjust servings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(override: servings) }
                        .disabled(isSaving || !servings.isFinite || servings < 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var loggedAmountDescription: String {
        item.contributions.map { contribution in
            if item.isMealFallback {
                return "\(contribution.amount.cleanAmount) logged meal serving(s)"
            }
            guard let food = item.food else { return "Logged quantity unavailable." }
            let portionLabel = food.portion(id: contribution.portionID)?.label ?? food.servingDescription ?? "serving"
            return "\(contribution.amount.cleanAmount) \(contribution.unit.title) of \(food.name) · \(portionLabel)"
        }.joined(separator: "\n")
    }

    private var calculationDescription: String {
        let lines = item.contributions.map { contribution in
            if contribution.isMealFallback {
                return "The meal has a meat classification but no matching classified ingredient, so the logged meal serving count is used."
            }
            guard let food = item.food else { return "Serving amount unavailable." }
            let portion = food.portion(id: contribution.portionID)
            let portionLabel = portion?.label ?? food.servingDescription ?? "serving"
            if contribution.unit == .serving {
                return "The log uses servings, so \(contribution.amount.cleanAmount) \(portionLabel) serving(s) count as \(contribution.calculatedServings.cleanAmount) servings."
            }
            let grams = contribution.unit.grams(for: contribution.amount, food: food, portionID: contribution.portionID)
            let servingGrams = portion?.grams ?? food.servingGrams ?? food.baseAmountGrams
            return "\(contribution.amount.cleanAmount) \(contribution.unit.title) converts to \(grams.cleanAmount) g. Divide by \(servingGrams.cleanAmount) g per \(portionLabel) to get \(contribution.calculatedServings.cleanAmount) servings."
        }
        return lines.joined(separator: "\n")
    }

    private func save(override: Double?) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        diary.run(operation: "meat_servings_override.update") {
            do {
                try await diary.updateMeatServingsOverride(
                    contributions: item.contributions,
                    servings: override
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
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
