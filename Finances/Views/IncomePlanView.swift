import SwiftUI
import SwiftData

struct IncomePlanView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?

    // Season & pay schedule
    @State private var usesSeasonDates = false
    @State private var seasonStart: Date = .now
    @State private var seasonEnd: Date = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now
    @State private var weeksInSeason: Double = 12
    @State private var payFrequency: PayFrequency = .biweekly

    // Regular hours
    @State private var hoursPerWeek: Double = 30
    @State private var hourlyWage: Double = 15

    // Overtime & extras
    @State private var overtimeHoursPerWeek: Double = 0
    @State private var overtimeMultiplier: Double = 1.5
    @State private var tipsPerWeek: Double = 0
    @State private var oneTimeBonuses: Double = 0

    // Target override
    @State private var useOverride = false
    @State private var totalTargetOverride: Double = 0

    // Year budget (rates are edited as percents)
    @State private var allowancePerWeek: Double = 15
    @State private var spendingPerWeek: Double = 45
    @State private var gasPerTwoWeeks: Double = 50
    @State private var savingsGoal: Double = 1600
    @State private var startingMoney: Double = 0
    @State private var taxPercent: Double = 0
    @State private var stockReturnPercent: Double = 7
    @State private var savingsReturnPercent: Double = 2

    private static let percentScale: Double = 100

    /// Weeks used for every calculation: derived from the dates when enabled, otherwise typed in.
    private var effectiveWeeks: Double {
        usesSeasonDates ? IncomeBreakdown.weeks(from: seasonStart, to: seasonEnd) : weeksInSeason.clampedNonNegative
    }

    /// Live preview of the plan built from the unsaved form values.
    private var preview: IncomeBreakdown {
        IncomeBreakdown(
            hoursPerWeek: hoursPerWeek.clampedNonNegative,
            hourlyWage: hourlyWage.clampedNonNegative,
            weeksInSeason: effectiveWeeks,
            overtimeHoursPerWeek: overtimeHoursPerWeek.clampedNonNegative,
            overtimeMultiplier: overtimeMultiplier.clampedNonNegative,
            tipsPerWeek: tipsPerWeek.clampedNonNegative,
            oneTimeBonuses: oneTimeBonuses.clampedNonNegative,
            totalTargetOverride: useOverride ? totalTargetOverride.clampedNonNegative : 0,
            payFrequency: payFrequency
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "Your schedule, pay and budget. Changes save when you leave this screen.", title: "Plan settings")

                seasonSection
                hoursSection
                extrasSection
                targetSection
                budgetSection
                breakdownSection

                HStack {
                    if let plan {
                        Text("Last saved \(plan.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save plan") {
                        save()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }

                GroupBox("How it’s used") {
                    Text("Gas, spending and savings get fixed amounts. Stocks gets whatever is left. Each paycheck is split by those shares on the Overview checklist.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Plan settings")
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .onChange(of: plan?.updatedAt) { _, _ in
            load()
        }
    }

    // MARK: - Sections

    private var seasonSection: some View {
        GroupBox("Season & pay schedule") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Calculate weeks from start and end dates", isOn: $usesSeasonDates)

                if usesSeasonDates {
                    labeledField("First day of work") {
                        DatePicker("", selection: $seasonStart, displayedComponents: .date)
                            .labelsHidden()
                    }
                    labeledField("Last day of work") {
                        DatePicker("", selection: $seasonEnd, in: seasonStart..., displayedComponents: .date)
                            .labelsHidden()
                    }
                    labeledField("Weeks in season") {
                        Text(effectiveWeeks.formatted(.number.precision(.fractionLength(0...1)))).animatedNumber(effectiveWeeks)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else {
                    labeledField("Weeks in season") {
                        TextField("12", value: $weeksInSeason, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                }

                labeledField("Pay frequency") {
                    Picker("", selection: $payFrequency) {
                        ForEach(PayFrequency.allCases) { frequency in
                            Text(frequency.label).tag(frequency)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var hoursSection: some View {
        GroupBox("Regular hours") {
            VStack(alignment: .leading, spacing: 14) {
                labeledField("Hours per week") {
                    TextField("30", value: $hoursPerWeek, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
                labeledField("Hourly wage") {
                    TextField("15", value: $hourlyWage, format: .currency(code: currencyCode))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var extrasSection: some View {
        GroupBox("Overtime & extras") {
            VStack(alignment: .leading, spacing: 14) {
                labeledField("Overtime hours / week") {
                    TextField("0", value: $overtimeHoursPerWeek, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
                labeledField("Overtime rate") {
                    TextField("1.5", value: $overtimeMultiplier, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 80)
                    Text("× wage = \(MoneyFormat.string(hourlyWage.clampedNonNegative * overtimeMultiplier.clampedNonNegative))/hr").animatedNumber(hourlyWage * overtimeMultiplier)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                labeledField("Tips per week") {
                    TextField("0", value: $tipsPerWeek, format: .currency(code: currencyCode))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                }
                labeledField("One-time bonuses") {
                    TextField("0", value: $oneTimeBonuses, format: .currency(code: currencyCode))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                    Text("for the whole season")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var targetSection: some View {
        GroupBox("Target") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Use a fixed total target instead of the calculated amount", isOn: $useOverride)

                if useOverride {
                    labeledField("Total summer target") {
                        TextField("0", value: $totalTargetOverride, format: .currency(code: currencyCode))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var budgetSection: some View {
        GroupBox("Year budget") {
            VStack(alignment: .leading, spacing: 14) {
                moneyField("Allowance per week", value: $allowancePerWeek)
                moneyField("Spending per week", value: $spendingPerWeek)
                moneyField("Gas every two weeks", value: $gasPerTwoWeeks)
                moneyField("Savings goal", value: $savingsGoal, note: "for the school year")
                moneyField("Starting money", value: $startingMoney, note: "goes into Stocks")
                percentField("Tax withheld", value: $taxPercent)
                percentField("Stock return per year", value: $stockReturnPercent)
                percentField("Savings reward per year", value: $savingsReturnPercent)
            }
            .padding(.vertical, 8)
        }
    }

    private func moneyField(_ title: String, value: Binding<Double>, note: String? = nil) -> some View {
        labeledField(title) {
            TextField("0", value: value, format: .currency(code: currencyCode))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
            if let note {
                Text(note).foregroundStyle(.secondary)
            }
        }
    }

    private func percentField(_ title: String, value: Binding<Double>) -> some View {
        labeledField(title) {
            TextField("0", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 80)
            Text("%").foregroundStyle(.secondary)
        }
    }

    private var breakdownSection: some View {
        GroupBox("Breakdown") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 8) {
                    breakdownRow("Regular pay", detail: "\(hoursPerWeek.clampedNonNegative.formatted()) hrs × \(weeksLabel)", value: preview.regularPay)
                    breakdownRow("Overtime", detail: "\(overtimeHoursPerWeek.clampedNonNegative.formatted()) hrs × \(weeksLabel)", value: preview.overtimePay)
                    breakdownRow("Tips", detail: "\(MoneyFormat.string(tipsPerWeek.clampedNonNegative)) × \(weeksLabel)", value: preview.tipsTotal)
                    breakdownRow("One-time bonuses", detail: nil, value: oneTimeBonuses.clampedNonNegative)
                    Divider()
                    breakdownRow("Calculated total", detail: nil, value: preview.computedTotal)
                        .fontWeight(.semibold)

                    if preview.usesOverride {
                        let difference = preview.plannedIncome - preview.computedTotal
                        breakdownRow("Target", detail: differenceLabel(difference), value: preview.plannedIncome)
                            .fontWeight(.semibold)
                    }
                }

                Divider()

                HStack {
                    Text("Planned income")
                        .font(.headline)
                    Spacer()
                    Text(MoneyFormat.string(preview.plannedIncome)).animatedNumber(preview.plannedIncome)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SummaryCard(
                        title: "Per paycheck",
                        value: MoneyFormat.string(preview.perPaycheck),
                        footnote: "\(preview.paychecks.formatted(.number.precision(.fractionLength(0...1)))) paychecks, \(payFrequency.label.lowercased())"
                    )
                    SummaryCard(title: "Per week", value: MoneyFormat.string(preview.perWeek), footnote: weeksLabel)
                    SummaryCard(title: "Per month", value: MoneyFormat.string(preview.perMonth), footnote: "Average month")
                    SummaryCard(
                        title: "Total hours",
                        value: preview.totalHours.formatted(.number.precision(.fractionLength(0...1))),
                        footnote: "\((hoursPerWeek.clampedNonNegative + overtimeHoursPerWeek.clampedNonNegative).formatted()) hrs/wk incl. overtime"
                    )
                    SummaryCard(title: "Effective hourly", value: MoneyFormat.string(preview.effectiveHourly), footnote: "Including overtime, tips & bonuses")
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var weeksLabel: String {
        "\(effectiveWeeks.formatted(.number.precision(.fractionLength(0...1)))) wks"
    }

    private func differenceLabel(_ difference: Double) -> String {
        if abs(difference) < 0.5 { return "Matches calculated total" }
        let amount = MoneyFormat.string(abs(difference))
        return difference > 0 ? "\(amount) above calculated" : "\(amount) below calculated"
    }

    private func breakdownRow(_ title: String, detail: String?, value: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormat.string(value))
                .animatedNumber(value)
                .monospacedDigit()
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .frame(width: 170, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func load() {
        guard let plan else { return }
        usesSeasonDates = plan.usesSeasonDates
        seasonStart = plan.seasonStart
        seasonEnd = plan.seasonEnd
        weeksInSeason = plan.weeksInSeason
        payFrequency = plan.payFrequency
        hoursPerWeek = plan.hoursPerWeek
        hourlyWage = plan.hourlyWage
        overtimeHoursPerWeek = plan.overtimeHoursPerWeek
        overtimeMultiplier = plan.overtimeMultiplier
        tipsPerWeek = plan.tipsPerWeek
        oneTimeBonuses = plan.oneTimeBonuses
        useOverride = plan.usesOverride
        totalTargetOverride = plan.totalTargetOverride
        allowancePerWeek = plan.allowancePerWeek
        spendingPerWeek = plan.spendingPerWeek
        gasPerTwoWeeks = plan.gasPerTwoWeeks
        savingsGoal = plan.savingsGoal
        startingMoney = plan.startingMoney
        taxPercent = plan.taxRate * Self.percentScale
        stockReturnPercent = plan.stockReturn * Self.percentScale
        savingsReturnPercent = plan.savingsReturn * Self.percentScale
    }

    private func save() {
        let target = plan ?? {
            let created = IncomePlan()
            modelContext.insert(created)
            return created
        }()

        // Only touch values that really changed, so leaving the screen without edits doesn't
        // save and make every other screen redraw.
        var changed = false
        func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<IncomePlan, Value>, _ value: Value) {
            guard target[keyPath: keyPath] != value else { return }
            target[keyPath: keyPath] = value
            changed = true
        }

        assign(\.usesSeasonDates, usesSeasonDates)
        assign(\.seasonStart, seasonStart)
        assign(\.seasonEnd, max(seasonStart, seasonEnd))
        // Store the derived weeks so other screens can keep reading `weeksInSeason` directly.
        assign(\.weeksInSeason, effectiveWeeks)
        assign(\.payFrequency, payFrequency)
        assign(\.hoursPerWeek, hoursPerWeek.clampedNonNegative)
        assign(\.hourlyWage, hourlyWage.clampedNonNegative)
        assign(\.overtimeHoursPerWeek, overtimeHoursPerWeek.clampedNonNegative)
        assign(\.overtimeMultiplier, overtimeMultiplier.clampedNonNegative)
        assign(\.tipsPerWeek, tipsPerWeek.clampedNonNegative)
        assign(\.oneTimeBonuses, oneTimeBonuses.clampedNonNegative)
        assign(\.totalTargetOverride, useOverride ? totalTargetOverride.clampedNonNegative : 0)
        assign(\.allowancePerWeek, allowancePerWeek.clampedNonNegative)
        assign(\.spendingPerWeek, spendingPerWeek.clampedNonNegative)
        assign(\.gasPerTwoWeeks, gasPerTwoWeeks.clampedNonNegative)
        assign(\.savingsGoal, savingsGoal.clampedNonNegative)
        assign(\.startingMoney, startingMoney.clampedNonNegative)
        assign(\.taxRate, min(1, taxPercent.clampedNonNegative / Self.percentScale))
        assign(\.stockReturn, stockReturnPercent / Self.percentScale)
        assign(\.savingsReturn, savingsReturnPercent / Self.percentScale)

        guard changed || plan == nil else { return }
        target.updatedAt = .now
        modelContext.saveChanges()
    }
}
