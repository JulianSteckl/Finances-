import SwiftUI
import SwiftData
import Charts

struct PaychecksView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?
    let ledger: Ledger

    @State private var pendingDelete: MoneyEntry?

    var body: some View {
        let inputs = plan?.inputs ?? .base
        let yearPlan = YearPlan(inputs)
        let paidByWeek = ledger.weeklyPay(from: plan?.weekNumberingStart(firstPaycheck: ledger.paychecks.first?.date) ?? .now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow: "Log a paycheck, purchase, gas fill-up or allowance", title: "Paychecks & log")
                // The form keeps its own state, so typing only redraws the form and its split preview.
                NewEntrySection(inputs: inputs, yearPlan: yearPlan, spentThisWeek: ledger.spentThisWeek, gasBalance: ledger.balance(of: .gas))
                PayForecastCard(yearPlan: yearPlan, paidByWeek: paidByWeek)
                logCard
            }
            .padding(Theme.pagePadding)
        }
        .background(Theme.background)
        .navigationTitle("Paychecks & log")
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { entry in
            Button("Delete \(entry.title)", role: .destructive) { delete(entry) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var logCard: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            CardTitle(title: "Log", trailing: "\(ledger.entries.count) entries")
            if ledger.entries.isEmpty {
                EmptyHint(text: "Nothing logged yet.")
            }
            ForEach(ledger.entries) { entry in
                Divider()
                HStack(spacing: 8) {
                    EntryRow(entry: entry)
                    Button {
                        pendingDelete = entry
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.muted)
                    .help("Delete entry")
                    .accessibilityLabel("Delete \(entry.title)")
                }
            }
        }
        .card()
    }

    private func delete(_ entry: MoneyEntry) {
        if entry.kind == .paycheck {
            // Checklist moves belong to their paycheck, so they go with it.
            ledger.transfers(from: entry).forEach(modelContext.delete)
        }
        modelContext.delete(entry)
        modelContext.saveChanges()
        pendingDelete = nil
    }
}

/// The "New entry" form and its live split preview.
struct NewEntrySection: View {
    @Environment(\.modelContext) private var modelContext
    let inputs: PlanInputs
    let yearPlan: YearPlan
    let spentThisWeek: Double
    let gasBalance: Double

    @State private var kind: EntryKind = .paycheck
    @State private var amount: Double = 0
    @State private var hours: Double = 0
    @State private var date: Date = .now
    @State private var note = ""

    var body: some View {
        ResponsiveRow(leadingWeight: 0.9) {
            entryForm
        } trailing: {
            SplitPreviewCard(yearPlan: yearPlan, amount: kind == .paycheck && amount > 0 ? amount : yearPlan.weeklyPay)
        }
        .onAppear(perform: resetDraft)
    }

    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "New entry")
            Picker("Type", selection: $kind) {
                ForEach(EntryKind.loggable) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: kind) { _, _ in resetAmount() }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    field("Amount") {
                        TextField("Amount", value: $amount, format: MoneyFormat.currency)
                    }
                    if kind == .paycheck {
                        field("Hours worked") { TextField("Hours", value: $hours, format: .number) }
                    } else {
                        field("What was it?") { TextField("e.g. Lunch", text: $note) }
                    }
                }
                GridRow {
                    field("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                    }
                }
            }
            Text(hint).font(.caption).foregroundStyle(Theme.muted)
            Button("Save entry", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amount <= 0)
                .keyboardShortcut(.defaultAction)
        }
        .textFieldStyle(.roundedBorder)
        .card()
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private var hint: String {
        switch kind {
        case .paycheck:
            let perHour = hours > 0 ? MoneyFormat.string(amount / hours) : "—"
            return "Works out to \(perHour) an hour (plan: \(MoneyFormat.string(inputs.hourlyWage)))"
        case .spending:
            return "Left this week after this: \(MoneyFormat.string(inputs.spendingPerWeek - spentThisWeek - amount))"
        case .gas:
            return "Gas pot after this: \(MoneyFormat.string(gasBalance - amount))"
        case .allowance, .transfer:
            return "Goes straight into Spending"
        }
    }

    private func save() {
        guard amount > 0 else { return }
        let entry = MoneyEntry(
            amount: amount,
            date: date,
            note: kind == .paycheck ? "" : note.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            hours: kind == .paycheck ? max(0, hours) : 0
        )
        modelContext.insert(entry)
        modelContext.saveChanges()
        resetDraft()
    }

    private func resetDraft() {
        note = ""
        date = .now
        hours = inputs.hoursPerWeek
        resetAmount()
    }

    private func resetAmount() {
        switch kind {
        case .paycheck: amount = (yearPlan.weeklyPay * 100).rounded() / 100
        case .allowance: amount = inputs.allowancePerWeek
        default: amount = 0
        }
    }
}

struct SplitPreviewCard: View {
    let yearPlan: YearPlan
    let amount: Double

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let shares = yearPlan.paycheckShares
        let split = yearPlan.split(paycheck: amount)
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Move your money", trailing: "Split of \(MoneyFormat.string(amount))")
            BucketSplitBar(shares: shares, height: 14)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Bucket.allCases) { bucket in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            BucketDot(bucket: bucket)
                            Text("\(bucket.name) · \(((shares[bucket] ?? 0) * 100).formatted(.number.precision(.fractionLength(1))))%")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text(MoneyFormat.string(split[bucket] ?? 0)).font(.system(size: 20, weight: .bold)).monospacedDigit()
                        Text(bucket.rule).font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                }
            }
            Text("Shares come from your plan, so every paycheck fills each bucket by the same percentage. Allowance goes straight to Spending.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }
}

struct PayForecastCard: View {
    let yearPlan: YearPlan
    let paidByWeek: [Double]

    private struct Point: Identifiable {
        let line: String
        let week: Double
        let total: Double
        var id: String { "\(line)-\(week)" }
    }

    private var forecast: PayForecast {
        PayForecast(paid: paidByWeek, expectedPerWeek: yearPlan.weeklyPay, totalWeeks: yearPlan.inputs.weeksOfWork)
    }

    private var points: [Point] {
        var result = [Point(line: "Base plan", week: 0, total: 0),
                      Point(line: "Base plan", week: yearPlan.inputs.weeksOfWork, total: yearPlan.jobTotal)]
        var running = 0.0
        result.append(Point(line: "Earned", week: 0, total: 0))
        for (index, pay) in paidByWeek.enumerated() {
            running += pay
            result.append(Point(line: "Earned", week: Double(index + 1), total: running))
        }
        result.append(Point(line: "Forecast", week: forecast.weeksWorked, total: running))
        result.append(Point(line: "Forecast", week: max(forecast.weeksWorked, yearPlan.inputs.weeksOfWork), total: forecast.projectedTotal))
        return result
    }

    var body: some View {
        let difference = forecast.projectedTotal - yearPlan.jobTotal
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Pay forecast")
            ResponsiveRow(minWideWidth: 600, leadingWeight: 2.4) {
                chart
            } trailing: {
                VStack(alignment: .leading, spacing: 12) {
                    stat("Weekly estimate", MoneyFormat.string(forecast.weeklyEstimate), "(earned + 3 × base week) ÷ (weeks + 3)")
                    stat("Projected summer pay", MoneyFormat.whole(forecast.projectedTotal),
                         "\(MoneyFormat.whole(forecast.earned)) earned in \(Int(forecast.weeksWorked)) weeks")
                    stat("Versus base plan", (difference >= 0 ? "+" : "−") + MoneyFormat.whole(abs(difference)),
                         difference >= 0 ? "On track for the \(MoneyFormat.whole(yearPlan.jobTotal)) plan" : "Stocks get a little less this year")
                }
            }
        }
        .card()
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(x: .value("Week", point.week), y: .value("Total", point.total), series: .value("Line", point.line))
                .foregroundStyle(point.line == "Base plan" ? Theme.muted : Theme.ink)
                .lineStyle(StrokeStyle(lineWidth: point.line == "Base plan" ? 1.5 : 2.5, dash: point.line == "Forecast" ? [6, 4] : []))
        }
        .chartXScale(domain: 0...max(1, yearPlan.inputs.weeksOfWork))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text(MoneyFormat.compact(value.as(Double.self) ?? 0)) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel { Text("Wk \(Int(value.as(Double.self) ?? 0))") }
            }
        }
        .frame(height: 210)
        .accessibilityLabel("Total pay so far, the forecast, and the base plan")
    }

    private func stat(_ label: String, _ value: String, _ footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 20, weight: .bold)).monospacedDigit()
            Text(footnote).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}
