import SwiftUI
import SwiftData
import Charts

/// Everything the Overview shows, worked out once per redraw.
struct OverviewSnapshot {
    let inputs: PlanInputs
    let yearPlan: YearPlan
    let ledger: Ledger
    let paidByWeek: [Double]
    let projection: [Bucket: [Double]]
    let currentWeek: Int

    init(plan: IncomePlan?, ledger: Ledger, now: Date = .now) {
        let inputs = plan?.inputs ?? .base
        let yearPlan = YearPlan(inputs)
        let start = plan?.weekNumberingStart(firstPaycheck: ledger.paychecks.first?.date) ?? now
        let paidByWeek = ledger.weeklyPay(from: start)
        self.inputs = inputs
        self.yearPlan = yearPlan
        self.ledger = ledger
        self.paidByWeek = paidByWeek
        self.projection = yearPlan.projection(paid: paidByWeek)
        self.currentWeek = WeekCounter.week(of: now, from: start)
    }

    var savedAndInvestedAtYearEnd: Double {
        (projection[.stocks]?.last ?? 0) + (projection[.savings]?.last ?? 0)
    }
}

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?
    let ledger: Ledger
    let onLogEntry: () -> Void

    private static let recentCount = 6

    var body: some View {
        let snapshot = OverviewSnapshot(plan: plan, ledger: ledger)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(snapshot)
                kpis(snapshot)
                ResponsiveRow {
                    YearOutlookCard(series: snapshot.projection, weeksOfWork: snapshot.inputs.weeksOfWork, currentWeek: snapshot.currentWeek)
                } trailing: {
                    SpendingWeekCard(ledger: ledger, weeklyBudget: snapshot.inputs.spendingPerWeek, pot: ledger.balance(of: .spending))
                }
                ResponsiveRow(leadingWeight: 1.3) {
                    WeeklyPayCard(yearPlan: snapshot.yearPlan, paidByWeek: snapshot.paidByWeek)
                } trailing: {
                    MoveMoneyCard(yearPlan: snapshot.yearPlan, ledger: ledger, onToggle: toggle)
                }
                recentActivity
            }
            .padding(Theme.pagePadding)
        }
        .background(Theme.background)
        .navigationTitle("Overview")
    }

    private func header(_ snapshot: OverviewSnapshot) -> some View {
        HStack(alignment: .bottom) {
            PageHeader(eyebrow: weekLabel(snapshot), title: "Overview")
            Spacer()
            Button(action: onLogEntry) {
                Label("Log entry", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("n")
        }
    }

    private func weekLabel(_ snapshot: OverviewSnapshot) -> String {
        let summerWeeks = Int(snapshot.inputs.weeksOfWork.rounded(.up))
        let week = snapshot.currentWeek
        return week <= summerWeeks
            ? "Week \(week) of \(summerWeeks) · summer job"
            : "Week \(week) of 52 · school year"
    }

    private func kpis(_ snapshot: OverviewSnapshot) -> some View {
        let yearPlan = snapshot.yearPlan
        let inputs = snapshot.inputs
        let savings = ledger.balance(of: .savings)
        let stocks = ledger.balance(of: .stocks)
        let savedGoal = yearPlan.yearTotal(for: .stocks) + yearPlan.yearTotal(for: .savings)
        let yearEnd = snapshot.savedAndInvestedAtYearEnd
        let spent = ledger.spentThisWeek
        let budget = inputs.spendingPerWeek
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
            KPITile(label: "Saved + invested", value: MoneyFormat.whole(savings + stocks),
                    progress: savedGoal > 0 ? (savings + stocks) / savedGoal : 0, tint: Bucket.savings.color,
                    footnote: "Savings \(MoneyFormat.whole(savings)) · Stocks \(MoneyFormat.whole(stocks))")
            KPITile(label: "Earned this summer", value: MoneyFormat.whole(ledger.earned),
                    progress: yearPlan.jobTotal > 0 ? ledger.earned / yearPlan.jobTotal : 0,
                    footnote: "\(percent(ledger.earned, of: yearPlan.jobTotal)) of \(MoneyFormat.whole(yearPlan.jobTotal)) plan")
            KPITile(label: "Projected at week 52", value: MoneyFormat.whole(yearEnd), progress: 1,
                    footnote: "Plan is \(MoneyFormat.whole(savedGoal)) before \(percentText(inputs.stockReturn)) / \(percentText(inputs.savingsReturn)) growth")
            KPITile(label: "Left to spend this week", value: MoneyFormat.string(budget - spent),
                    progress: budget > 0 ? (budget - spent) / budget : 0, tint: Bucket.spending.color,
                    footnote: "\(MoneyFormat.string(spent)) spent of \(MoneyFormat.whole(budget)) budget")
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardTitle(title: "Recent activity")
                Button("See full log", action: onLogEntry).buttonStyle(.link)
            }
            if ledger.entries.isEmpty {
                EmptyHint(text: "Nothing logged yet. Log your first paycheck to get started.")
            } else {
                ForEach(Array(ledger.entries.prefix(Self.recentCount))) { entry in
                    Divider()
                    EntryRow(entry: entry)
                }
            }
        }
        .card()
    }

    private func toggle(_ bucket: Bucket, paycheck: MoneyEntry, amount: Double) {
        if let existing = ledger.transfer(from: paycheck, to: bucket) {
            modelContext.delete(existing)
        } else {
            let rounded = (amount * 100).rounded() / 100
            modelContext.insert(MoneyEntry(amount: rounded, kind: .transfer, bucket: bucket, linkedPaycheckID: paycheck.entryID))
        }
        modelContext.saveChanges()
    }

    private func percent(_ value: Double, of total: Double) -> String {
        total > 0 ? "\(Int((value / total * 100).rounded()))%" : "0%"
    }

    private func percentText(_ rate: Double) -> String {
        "\((rate * 100).formatted(.number.precision(.fractionLength(0...1))))%"
    }
}

enum WeekCounter {
    static let weeksPerYear = 52

    /// 1-based week number of `date`, counted from `start`, kept within 1...52.
    static func week(of date: Date, from start: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: date).day ?? 0
        return min(weeksPerYear, max(1, days / 7 + 1))
    }
}

// MARK: - Cards

struct YearOutlookCard: View {
    let series: [Bucket: [Double]]
    let weeksOfWork: Double
    let currentWeek: Int

    private struct Point: Identifiable {
        let bucket: Bucket
        let week: Int
        let value: Double
        var id: String { "\(bucket.rawValue)-\(week)" }
    }

    private var points: [Point] {
        Bucket.allCases.flatMap { bucket in
            (series[bucket] ?? []).enumerated().map { Point(bucket: bucket, week: $0.offset, value: $0.element) }
        }
    }

    private var maxValue: Double {
        max(1000, ((points.map(\.value).max() ?? 0) / 1000).rounded(.up) * 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(title: "Year outlook by bucket")
                legend
            }
            chart.frame(height: 240)
            Text("Spending and gas fill up during the summer, then run down to $0 by week 52. Stocks and savings keep growing all year.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(Bucket.allCases) { bucket in
                HStack(spacing: 5) {
                    Capsule().fill(bucket.color).frame(width: 10, height: 3)
                    Text(bucket.name).foregroundStyle(Theme.muted)
                    Text(MoneyFormat.whole(series[bucket]?.last ?? 0)).fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
    }

    private var chart: some View {
        Chart {
            RectangleMark(
                xStart: .value("Week", 0), xEnd: .value("Week", weeksOfWork),
                yStart: .value("Amount", 0), yEnd: .value("Amount", maxValue)
            )
            .foregroundStyle(Theme.summerShade)
            ForEach(points) { point in
                LineMark(x: .value("Week", point.week), y: .value("Amount", point.value), series: .value("Bucket", point.bucket.name))
                    .foregroundStyle(point.bucket.color)
                    .lineStyle(StrokeStyle(lineWidth: point.bucket == .stocks ? 2.5 : 2, lineJoin: .round, dash: point.bucket.dash))
            }
            RuleMark(x: .value("Today", currentWeek))
                .foregroundStyle(Theme.ink)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Today").font(.caption2.weight(.semibold))
                }
        }
        .chartXScale(domain: 0...52)
        .chartYScale(domain: 0...maxValue)
        .chartXAxis {
            AxisMarks(values: [1, 13, 26, 39, 52]) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text("Wk \(value.as(Int.self) ?? 0)") }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text(MoneyFormat.compact(value.as(Double.self) ?? 0)) }
            }
        }
        .accessibilityLabel("Bucket balances across 52 weeks")
    }
}

struct SpendingWeekCard: View {
    let ledger: Ledger
    let weeklyBudget: Double
    let pot: Double

    private static let ringSize: CGFloat = 112
    private static let ringWidth: CGFloat = 12

    var body: some View {
        let spent = ledger.spentThisWeek
        let left = weeklyBudget - spent
        let daysLeft = ledger.daysLeftThisWeek
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Spending this week")
            HStack(spacing: 18) {
                ring(left: left)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resets at the start of next week").foregroundStyle(Theme.muted)
                    Text("\(MoneyFormat.string(max(0, left) / Double(daysLeft))) a day for \(daysLeft) days")
                    Text("Spending pot: \(MoneyFormat.whole(pot))").foregroundStyle(Theme.muted)
                }
                .font(.callout)
            }
            purchases
        }
        .card()
    }

    private func ring(left: Double) -> some View {
        ZStack {
            Circle().stroke(Theme.chip, lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: weeklyBudget > 0 ? min(1, max(0, left / weeklyBudget)) : 0)
                .stroke(Bucket.spending.color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(MoneyFormat.string(left)).font(.system(size: 18, weight: .bold)).monospacedDigit()
                Text("left of \(MoneyFormat.whole(weeklyBudget))").font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityElement(children: .combine)
    }

    private var purchases: some View {
        let items = ledger.purchasesThisWeek
        return VStack(spacing: 0) {
            if items.isEmpty {
                EmptyHint(text: "No purchases yet this week.")
            }
            ForEach(items) { item in
                Divider()
                HStack {
                    Text(item.title)
                    Text("· \(item.date.formatted(.dateTime.weekday(.abbreviated)))").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(MoneyFormat.signed(-item.amount)).fontWeight(.semibold).monospacedDigit()
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct WeeklyPayCard: View {
    let yearPlan: YearPlan
    let paidByWeek: [Double]

    private struct Bar: Identifiable {
        let week: Int
        let amount: Double
        let isPaid: Bool
        var id: Int { week }
    }

    private var bars: [Bar] {
        let weeks = max(1, Int(yearPlan.inputs.weeksOfWork.rounded(.up)))
        return (1...weeks).map { week in
            week <= paidByWeek.count
                ? Bar(week: week, amount: paidByWeek[week - 1], isPaid: true)
                : Bar(week: week, amount: yearPlan.expectedPay(inWeek: week), isPaid: false)
        }
    }

    var body: some View {
        let forecast = PayForecast(paid: paidByWeek, expectedPerWeek: yearPlan.weeklyPay, totalWeeks: yearPlan.inputs.weeksOfWork)
        let average = paidByWeek.isEmpty ? 0 : forecast.earned / Double(paidByWeek.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                CardTitle(title: "Weekly pay")
                key(fill: Theme.ink, label: "Paid")
                key(fill: Theme.muted.opacity(0.3), label: "Expected")
            }
            chart
            HStack(spacing: 20) {
                stat("Average", MoneyFormat.whole(average))
                stat("Hours", "\(yearPlan.inputs.hoursPerWeek.formatted()) / wk")
                stat("Forecast", MoneyFormat.whole(forecast.projectedTotal))
            }
        }
        .card()
    }

    private var chart: some View {
        Chart(bars) { bar in
            BarMark(x: .value("Week", bar.week), y: .value("Pay", bar.amount), width: .ratio(0.6))
                .foregroundStyle(bar.isPaid ? Theme.ink : Theme.muted.opacity(0.3))
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: bars.map(\.week)) { value in
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)") }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text(MoneyFormat.whole(value.as(Double.self) ?? 0)) }
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Pay for each week of the summer job")
    }

    private func key(fill: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Theme.muted)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
    }
}

struct MoveMoneyCard: View {
    let yearPlan: YearPlan
    let ledger: Ledger
    let onToggle: (Bucket, MoneyEntry, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let paycheck = ledger.latestPaycheck {
                checklist(for: paycheck)
            } else {
                CardTitle(title: "Move your money")
                EmptyHint(text: "Log a paycheck and this checklist shows how much goes into each bucket.")
            }
        }
        .card()
    }

    @ViewBuilder
    private func checklist(for paycheck: MoneyEntry) -> some View {
        let split = yearPlan.split(paycheck: paycheck.amount)
        let doneCount = Bucket.allCases.filter { ledger.transfer(from: paycheck, to: $0) != nil }.count
        CardTitle(title: "Move your money", trailing: "\(doneCount) of \(Bucket.allCases.count) done")
        Text("From your \(MoneyFormat.string(paycheck.amount)) paycheck on \(paycheck.date.formatted(date: .abbreviated, time: .omitted)), in Greenlight")
            .font(.caption).foregroundStyle(Theme.muted)
        BucketSplitBar(shares: yearPlan.paycheckShares, height: 8)
        ForEach(Bucket.allCases) { bucket in
            row(bucket: bucket, amount: split[bucket] ?? 0, done: ledger.transfer(from: paycheck, to: bucket) != nil) {
                onToggle(bucket, paycheck, split[bucket] ?? 0)
            }
        }
        if ledger.notYetMoved > 0.5 {
            Text("\(MoneyFormat.string(ledger.notYetMoved)) from all paychecks is not moved yet")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func row(bucket: Bucket, amount: Double, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundStyle(done ? Theme.ink : Theme.muted)
                BucketDot(bucket: bucket)
                Text("Move to \(bucket.name)")
                Spacer()
                Text(MoneyFormat.string(amount)).fontWeight(.semibold).monospacedDigit()
            }
            .foregroundStyle(done ? Theme.muted : Theme.ink)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

struct EntryRow: View {
    let entry: MoneyEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).fontWeight(.medium)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let bucket = entry.bucket {
                HStack(spacing: 6) {
                    BucketDot(bucket: bucket)
                    Text(bucket.name).font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(width: 90, alignment: .leading)
            }
            Text(amountText)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var amountText: String {
        switch entry.kind {
        case .paycheck, .allowance: MoneyFormat.signed(entry.amount)
        case .transfer: MoneyFormat.string(entry.amount)
        case .spending, .gas: MoneyFormat.signed(-entry.amount)
        }
    }
}
