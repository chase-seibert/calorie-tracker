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
            Text("\(summary.dayCount)")
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
            if summary.dayCount == 0 {
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
                average: summary.averageNutrients.carbs,
                minimum: summary.minimumNutrients.carbs,
                maximum: summary.maximumNutrients.carbs
            )
            macroRow(
                "Fat",
                color: AppTheme.fat,
                average: summary.averageNutrients.fat,
                minimum: summary.minimumNutrients.fat,
                maximum: summary.maximumNutrients.fat
            )
            macroRow(
                "Protein",
                color: AppTheme.protein,
                average: summary.averageNutrients.protein,
                minimum: summary.minimumNutrients.protein,
                maximum: summary.maximumNutrients.protein
            )
        }
        .padding(18)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var popularItem: some View {
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .font(.title2)
                .foregroundStyle(AppTheme.coral)
                .frame(width: 44, height: 44)
                .background(AppTheme.coral.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Most logged")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Text(summary.mostPopularItem ?? "No foods yet")
                    .font(.headline)
                    .lineLimit(2)
            }
            Spacer()
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
        average: Double,
        minimum: Double,
        maximum: Double
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
            Text("\(minimum.cleanAmount)–\(maximum.cleanAmount)g")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.muted)
        }
    }

    private func dateRange(from start: Date, through end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.month(.abbreviated).day().year())
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}
