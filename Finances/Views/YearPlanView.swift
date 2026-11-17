import SwiftUI
import SwiftData
import Charts

/// The 52-week plan with what-if sliders. Slider changes stay a draft until saved.
struct YearPlanView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?

    @State private var draft: PlanInputs = .base

    private var saved: PlanInputs { plan?.inputs ?? .base }
    private var yearPlan: YearPlan { YearPlan(draft) }
    private var isDraftChanged: Bool { draft != saved }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header.appearEffect(order: 0)
                results.appearEffect(order: 1)
                if yearPlan.isOverBudget {
                    Text("This plan spends more than it earns. Lower spending or the savings goal, or add hours, so Stocks isn't below $0.")
                        .fontWeight(.medium)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                ResponsiveRow(leadingWeight: 0.7) {
                    WhatIfCard(draft: $draft)
                } trailing: {
                    VStack(spacing: Theme.gap) {
                        MoneyFlowCard(yearPlan: yearPlan)
                        StocksGrowthCard(yearPlan: yearPlan)
                    }
                }
                .appearEffect(order: 2)
                MoneyInCard(yearPlan: yearPlan).appearEffect(order: 3)
            }
            .padding(Theme.pagePadding)
            .animation(Motion.quick, value: yearPlan.isOverBudget)
        }
        .background(Theme.background)
        .navigationTitle("Year plan")
        .onAppear { draft = saved }
        .onChange(of: plan?.updatedAt) { _, _ in draft = saved }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            PageHeader(eyebrow: isDraftChanged ? "What-if · not saved yet" : "Your plan · 52 weeks", title: "Year plan")
            Spacer()
            Button("Reset") { withAnimation(Motion.smooth) { draft = saved } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!isDraftChanged)
            Button("Save as my plan", action: saveDraft)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isDraftChanged || plan == nil)
        }
    }

    private var results: some View {
        let stocksChange = yearPlan.stocksTotal - YearPlan(saved).stocksTotal
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            KPITile(label: "Total money in", value: MoneyFormat.whole(yearPlan.totalIn),
                    footnote: "\(MoneyFormat.whole(yearPlan.jobTotal)) job + \(MoneyFormat.whole(yearPlan.allowanceTotal)) allowance")
            KPITile(label: "Into stocks this year", value: MoneyFormat.whole(yearPlan.stocksTotal),
                    footnote: isDraftChanged ? "\(stocksChange >= 0 ? "+" : "−")\(MoneyFormat.whole(abs(stocksChange))) vs your plan" : "Your plan")
            KPITile(label: "Saved + invested at week 52", value: MoneyFormat.whole(yearPlan.savedAndInvestedAtYearEnd()),
                    footnote: "Includes \(Self.percent(draft.stockReturn)) stocks, \(Self.percent(draft.savingsReturn)) savings growth")
            KPITile(label: "Each paycheck", value: MoneyFormat.whole(yearPlan.weeklyPay),
                    footnote: "\(draft.hoursPerWeek.formatted()) hrs × \(MoneyFormat.string(draft.hourlyWage))")
        }
    }

    private func saveDraft() {
        plan?.applyWhatIf(draft)
        modelContext.saveChanges()
    }

    static func percent(_ rate: Double) -> String {
        "\((rate * 100).formatted(.number.precision(.fractionLength(0...1))))%"
    }
}

struct WhatIfCard: View {
    @Binding var draft: PlanInputs

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(title: "What if…")
            slider("Hourly pay", value: $draft.hourlyWage, in: 12...30, step: 0.5,
                   text: MoneyFormat.string(draft.hourlyWage), hint: "Base plan: $20.00")
            slider("Hours per week", value: $draft.hoursPerWeek, in: 10...40, step: 0.5,
                   text: "\(draft.hoursPerWeek.formatted()) hrs", hint: "Base: Mon–Thu 5.5 hrs, Fri 7.5 hrs = 29.5")
            slider("Weeks of work", value: $draft.weeksOfWork, in: 6...16, step: 1,
                   text: "\(Int(draft.weeksOfWork)) weeks", hint: "Base plan: 13 weeks")
            slider("Spending per week", value: $draft.spendingPerWeek, in: 20...80, step: 5,
                   text: MoneyFormat.whole(draft.spendingPerWeek), hint: "Every $10 less a week is $520 more in stocks")
            slider("Savings goal", value: $draft.savingsGoal, in: 0...3000, step: 100,
                   text: MoneyFormat.whole(draft.savingsGoal), hint: "Base plan: $1,600 for the school year")
            slider("Stock return per year", value: $draft.stockReturn, in: 0...0.12, step: 0.005,
                   text: YearPlanView.percent(draft.stockReturn), hint: "Base plan: 7%")
        }
        .card()
    }

    private func slider(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, text: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).fontWeight(.medium)
                Spacer()
                Text(text).fontWeight(.bold).monospacedDigit().animatedNumber(text)
            }
            Slider(value: value, in: range, step: step) { Text(label) }
                .labelsHidden()
                .tint(Theme.ink)
            Text(hint).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct MoneyFlowCard: View {
    let yearPlan: YearPlan

    private var total: Double {
        max(1, Bucket.allCases.reduce(0) { $0 + yearPlan.yearTotal(for: $1) })
    }

    var body: some View {
        let shares = Dictionary(uniqueKeysWithValues: Bucket.allCases.map { ($0, yearPlan.yearTotal(for: $0) / total) })
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Where the year's money goes", trailing: "of \(MoneyFormat.whole(yearPlan.totalIn))")
            BucketSplitBar(shares: shares, height: 28)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(Bucket.allCases) { bucket in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            BucketDot(bucket: bucket)
                            Text(bucket.name)
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text(MoneyFormat.whole(yearPlan.yearTotal(for: bucket))).font(.system(size: 17, weight: .bold)).monospacedDigit()
                            .animatedNumber(yearPlan.yearTotal(for: bucket))
                        Text("\(Int(((shares[bucket] ?? 0) * 100).rounded()))%").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .card()
    }
}

struct StocksGrowthCard: View {
    let yearPlan: YearPlan
    @State private var reveal: Double = 0

    private struct Point: Identifiable {
        let line: String
        let year: Int
        let value: Double
        var id: String { "\(line)-\(year)" }
    }

    var body: some View {
        let growth = yearPlan.stocksOverYears()
        let points = growth.repeating.enumerated().map { Point(line: "Repeat", year: $0.offset, value: $0.element * reveal) }
            + growth.once.enumerated().map { Point(line: "Once", year: $0.offset, value: $0.element * reveal) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                CardTitle(title: "Stocks over 5 years", trailing: MoneyFormat.whole(growth.repeating.last ?? 0))
            }
            Chart(points) { point in
                if point.line == "Repeat" {
                    AreaMark(x: .value("Year", point.year), y: .value("Value", point.value))
                        .foregroundStyle(Bucket.stocks.color.opacity(0.08))
                }
                LineMark(x: .value("Year", point.year), y: .value("Value", point.value), series: .value("Line", point.line))
                    .foregroundStyle(point.line == "Repeat" ? Bucket.stocks.color : Theme.muted)
                    .lineStyle(StrokeStyle(lineWidth: point.line == "Repeat" ? 2.5 : 1.75, dash: point.line == "Once" ? [5, 4] : []))
            }
            .chartXAxis {
                AxisMarks(values: Array(0...5)) { value in
                    let year = value.as(Int.self) ?? 0
                    AxisValueLabel { Text(year == 0 ? "Now" : "Yr \(year)") }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { Text(MoneyFormat.compact(value.as(Double.self) ?? 0)) }
                }
            }
            .chartYScale(domain: 0...yMax(growth.repeating))
            .animation(Motion.smooth, value: growth.repeating)
            .frame(height: 200)
            .revealOnAppear($reveal)
            .accessibilityLabel("Stocks over five years, repeating the plan each summer or investing this year only")
            HStack(spacing: 16) {
                key(dashed: false, label: "Repeat this plan each summer")
                key(dashed: true, label: "This year only")
            }
            Text("Assumes a steady \(YearPlanView.percent(yearPlan.inputs.stockReturn)) a year. Real stock returns go up and down, so treat this as a rough guide, not a promise.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }

    /// Axis top rounded up to the next $2k, kept from the real values so it doesn't jump while lines grow in.
    private func yMax(_ values: [Double]) -> Double {
        max(1000, ((values.max() ?? 0) / 2000).rounded(.up) * 2000)
    }

    private func key(dashed: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 14, y: 1))
            }
            .stroke(dashed ? Theme.muted : Bucket.stocks.color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
            .frame(width: 14, height: 2)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct MoneyInCard: View {
    let yearPlan: YearPlan

    var body: some View {
        let inputs = yearPlan.inputs
        return VStack(alignment: .leading, spacing: 6) {
            CardTitle(title: "Money in")
            row("Summer job",
                "\(inputs.weeksOfWork.formatted()) weeks × \(inputs.hoursPerWeek.formatted()) hrs × \(MoneyFormat.string(inputs.hourlyWage))\(inputs.taxRate > 0 ? " after tax" : ", no tax withheld")",
                yearPlan.jobTotal)
            row("Allowance", "\(MoneyFormat.whole(inputs.allowancePerWeek)) a week × 52 weeks", yearPlan.allowanceTotal)
            row("Starting money", inputs.startingMoney > 0 ? "Goes into Stocks" : "Not set yet. Add it in Plan settings", inputs.startingMoney)
            Divider()
            HStack {
                Text("Total").fontWeight(.bold)
                Spacer()
                Text(MoneyFormat.whole(yearPlan.totalIn)).fontWeight(.bold).monospacedDigit()
            }
            .padding(.vertical, 6)
        }
        .card()
    }

    private func row(_ name: String, _ how: String, _ total: Double) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(name).fontWeight(.medium).frame(width: 130, alignment: .leading)
                Text(how).foregroundStyle(Theme.muted)
                Spacer()
                Text(MoneyFormat.whole(total)).fontWeight(.medium).monospacedDigit()
            }
            .padding(.vertical, 8)
        }
    }
}
