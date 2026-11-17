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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Income plan")
                        .font(.largeTitle.weight(.semibold))
                    Text("Estimate what you expect to earn this summer from your schedule, wage, overtime, and extras — or set a total target.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                seasonSection
                hoursSection
                extrasSection
                targetSection
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
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }

                GroupBox("How it’s used") {
                    Text("Allocations split this planned income into buckets. Tracking compares actual paychecks and spending against the plan.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Income Plan")
        .onAppear(perform: load)
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
                        Text(effectiveWeeks.formatted(.number.precision(.fractionLength(0...1))))
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
                    Text("× wage = \(MoneyFormat.string(hourlyWage.clampedNonNegative * overtimeMultiplier.clampedNonNegative))/hr")
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
                    Text(MoneyFormat.string(preview.plannedIncome))
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
    }

    private func save() {
        let target = plan ?? {
            let created = IncomePlan()
            modelContext.insert(created)
            return created
        }()

        target.usesSeasonDates = usesSeasonDates
        target.seasonStart = seasonStart
        target.seasonEnd = max(seasonStart, seasonEnd)
        // Store the derived weeks so other screens can keep reading `weeksInSeason` directly.
        target.weeksInSeason = effectiveWeeks
        target.payFrequency = payFrequency
        target.hoursPerWeek = hoursPerWeek.clampedNonNegative
        target.hourlyWage = hourlyWage.clampedNonNegative
        target.overtimeHoursPerWeek = overtimeHoursPerWeek.clampedNonNegative
        target.overtimeMultiplier = overtimeMultiplier.clampedNonNegative
        target.tipsPerWeek = tipsPerWeek.clampedNonNegative
        target.oneTimeBonuses = oneTimeBonuses.clampedNonNegative
        target.totalTargetOverride = useOverride ? totalTargetOverride.clampedNonNegative : 0
        target.updatedAt = .now
        try? modelContext.save()
    }
}
