import Charts
import SwiftUI

/// Where spending money goes, and which weeks go over.
struct TrendsView: View {
    let plan: IncomePlan?
    let ledger: Ledger

    @State private var range: Range = .quarter

    enum Range: Int, CaseIterable, Identifiable {
        case month = 4
        case quarter = 12
        case halfYear = 26
        var id: Int { rawValue }
        var label: String { "\(rawValue) weeks" }
    }

    var body: some View {
        let week = MoneyContext(plan: plan, ledger: ledger).spendingWeek
        let trends = SpendingTrends(
            purchases: ledger.entries.filter { $0.kind == .spending }.map { .init(date: $0.date, amount: $0.amount, category: $0.spendingCategory) },
            currentWeekStart: week.weekStart, weekLimit: range.rawValue, weeklyAmount: week.baseWeekly, calendar: ledger.calendar
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header.appearEffect(order: 0)
                if trends.isEmpty {
                    EmptyHint(text: "No purchases in this time. Log what you buy and your trends show up here.").card()
                } else {
                    tiles(trends, weeklyAmount: week.baseWeekly).appearEffect(order: 1)
                    WeeklySpendingCard(trends: trends, weeklyAmount: week.baseWeekly).appearEffect(order: 2)
                    ResponsiveRow(leadingWeight: 1) {
                        CategoryCard(trends: trends)
                    } trailing: {
                        DaysCard(trends: trends, calendar: ledger.calendar)
                    }
                    .appearEffect(order: 3)
                }
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Trends")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            PageHeader(title: "Trends")
            Spacer()
            Picker("Time", selection: $range.animation(Motion.smooth)) {
                ForEach(Range.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func tiles(_ trends: SpendingTrends, weeklyAmount: Double) -> some View {
        TileGridLayout {
            KPITile(label: "Spent", value: MoneyFormat.string(trends.total), footnote: "\(trends.weeks.count) week\(trends.weeks.count == 1 ? "" : "s")")
            KPITile(label: "Average week", value: MoneyFormat.string(trends.averagePerWeek), footnote: "Weekly amount \(MoneyFormat.string(weeklyAmount))")
            KPITile(label: "Weeks over", value: "\(trends.weeksOver) of \(trends.weeks.count)")
            KPITile(label: "Most spent on", value: trends.topCategory?.name ?? "—", footnote: trends.topCategory.map { MoneyFormat.string($0.amount) })
        }
    }
}

/// One bar per week, solid when it went over the weekly amount.
private struct WeeklySpendingCard: View {
    let trends: SpendingTrends
    let weeklyAmount: Double
    @State private var reveal: Double = 0

    private static let maxLabels = 8

    private func label(_ week: SpendingTrends.Week) -> String { week.start.formatted(.dateTime.month(.abbreviated).day()) }

    /// Every week is labelled when there are few, otherwise evenly spaced ones.
    private var axisLabels: [String] {
        let step = max(1, Int((Double(trends.weeks.count) / Double(Self.maxLabels)).rounded(.up)))
        return stride(from: 0, to: trends.weeks.count, by: step).map { label(trends.weeks[$0]) }
    }

    var body: some View {
        let top = max(10, max(weeklyAmount, trends.weeks.map(\.spent).max() ?? 0) * 1.15)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                CardTitle(title: "Spending by week")
                key(Theme.ink, "Over")
                key(Theme.muted.opacity(0.35), "Under")
                HStack(spacing: 5) {
                    Rectangle().fill(Theme.ink).frame(width: 12, height: 1)
                    Text("Weekly amount").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Chart {
                ForEach(trends.weeks) { week in
                    BarMark(x: .value("Week", label(week)), y: .value("Spent", week.spent * reveal), width: .ratio(0.6))
                        .foregroundStyle(week.spent > weeklyAmount + 0.005 ? Theme.ink : Theme.muted.opacity(0.35))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Weekly amount", weeklyAmount))
                    .foregroundStyle(Theme.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: axisLabels) { _ in AxisValueLabel() }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { Text(MoneyFormat.whole(value.as(Double.self) ?? 0)) }
                }
            }
            .frame(height: 220)
            .revealOnAppear($reveal)
            .accessibilityLabel("Spending for each week, against the weekly amount")
        }
        .card()
    }

    private func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

private struct CategoryCard: View {
    let trends: SpendingTrends

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Where it goes")
            ForEach(trends.categories) { item in
                let share = trends.total > 0 ? item.amount / trends.total : 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.name).fontWeight(.medium)
                        Spacer()
                        Text("\(Int((share * 100).rounded()))%").font(.caption).foregroundStyle(Theme.muted)
                        Text(MoneyFormat.string(item.amount)).fontWeight(.semibold).monospacedDigit().animatedNumber(item.amount)
                    }
                    ProgressBar(value: share, tint: item.category == nil ? Theme.muted.opacity(0.5) : Theme.ink, height: 8)
                }
            }
        }
        .card()
    }
}

private struct DaysCard: View {
    let trends: SpendingTrends
    let calendar: Calendar

    var body: some View {
        let top = max(1, trends.days.map(\.amount).max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "By day")
            ForEach(trends.days) { day in
                HStack(spacing: 12) {
                    Text(calendar.shortWeekdaySymbols[day.weekday - 1]).frame(width: 36, alignment: .leading)
                    ProgressBar(value: day.amount / top, tint: Theme.ink, height: 8)
                    Text(MoneyFormat.string(day.amount)).fontWeight(.semibold).monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                        .animatedNumber(day.amount)
                }
            }
        }
        .card()
    }
}
