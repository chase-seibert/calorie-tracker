import SwiftUI

struct StreakReportView: View {
    @EnvironmentObject private var diary: DiaryStore

    private var summary: StreakSummary { diary.currentStreak }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    streakHeader
                    explanation
                    if summary.dayCount > 0 {
                        calorieStats
                        macroStats
                        popularItem
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
        .analyticsScreen("streak")
    }

    private var streakHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(AppTheme.coral)
                .frame(width: 76, height: 76)
                .background(AppTheme.coral.opacity(0.16), in: Circle())
            Text(diary.isCalculatingStreak ? "…" : "\(summary.dayCount)")
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
            Text(summary.dayCount == 1 ? "day streak" : "day streak")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
            if let oldest = summary.dates.last, let newest = summary.dates.first {
                Text(dateRange(from: oldest, through: newest))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How streaks work", systemImage: "info.circle.fill")
                .font(.headline)
            Text("Your streak counts consecutive days with at least one food or meal logged. A day without food or a meal ends the streak. Today does not count against you until it is over.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
            if !diary.isCalculatingStreak, summary.dayCount == 0 {
                Text("Log food today to start a new streak.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var calorieStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calories")
                .font(.title3.weight(.bold))
            HStack(spacing: 12) {
                stat(
                    title: "Daily average",
                    value: Int(summary.averageNutrients.calories.rounded()).formatted(),
                    suffix: "cal"
                )
                stat(
                    title: "Range",
                    value: "\(Int(summary.minimumNutrients.calories.rounded()).formatted())–\(Int(summary.maximumNutrients.calories.rounded()).formatted())",
                    suffix: "cal"
                )
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var macroStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily macros")
                .font(.title3.weight(.bold))
            macroRow(
                "Carbs",
                color: AppTheme.carbs,
                average: summary.averageNutrients.carbs
            )
            macroRow(
                "Fat",
                color: AppTheme.fat,
                average: summary.averageNutrients.fat
            )
            macroRow(
                "Protein",
                color: AppTheme.protein,
                average: summary.averageNutrients.protein
            )
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var popularItem: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(AppTheme.coral)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.coral.opacity(0.12), in: Circle())
                Text("Frequent foods")
                    .font(.title3.weight(.bold))
            }

            if summary.frequentFoods.isEmpty {
                Text("No foods yet")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            } else {
                ForEach(summary.frequentFoods) { food in
                    HStack(spacing: 10) {
                        Text(food.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text("\(food.count) \(food.count == 1 ? "log" : "logs")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func stat(title: String, value: String, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(suffix)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.controlFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private func macroRow(
        _ title: String,
        color: Color,
        average: Double
    ) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("avg \(average.cleanAmount)g")
                .font(.subheadline.monospacedDigit())
        }
    }

    private func dateRange(from start: Date, through end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}
