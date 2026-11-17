import SwiftUI
import SwiftData

struct IncomePlanView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?

    @State private var hourlyWage: Double = 20
    @State private var mondayThursdayHours: Double = 4.5
    @State private var fridayHours: Double = 7.5
    @State private var summerStart = SeasonCalendar.season().summerStart
    @State private var summerEnd = SeasonCalendar.season().summerEnd
    @State private var schoolYearStart = SeasonCalendar.season().schoolYearStart
    @State private var schoolYearEnd = SeasonCalendar.season().schoolYearEnd
    @State private var useOverride = false
    @State private var totalTargetOverride: Double = 0

    private var weeklyHours: Double { (mondayThursdayHours * 4) + fridayHours }
    private var weeklyPay: Double { weeklyHours * hourlyWage }
    private var summerWeeks: Double { SeasonCalendar.weeks(from: summerStart, to: summerEnd) }
    private var schoolWeeks: Double { SeasonCalendar.weeks(from: schoolYearStart, to: schoolYearEnd) }

    private var previewIncome: Double {
        if useOverride {
            return totalTargetOverride.clampedNonNegative
        }
        return weeklyPay * summerWeeks
    }

    private var previewSafeWeekly: Double {
        let living = previewIncome * 0.5 // default hint if 50% left after 25/25 stocks+savings seed
        return schoolWeeks > 0 ? living / schoolWeeks : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Income plan")
                        .font(.largeTitle.weight(.semibold))
                    Text("Summer job schedule at \(MoneyFormat.string(hourlyWage))/hr (no tax), then stretch that pile through the school year.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Summer schedule") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Use a total summer target instead", isOn: $useOverride)

                        if useOverride {
                            labeledField("Total summer target") {
                                TextField("0", value: $totalTargetOverride, format: .currency(code: currencyCode))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 220)
                            }
                        } else {
                            labeledField("Hourly wage") {
                                TextField("20", value: $hourlyWage, format: .currency(code: currencyCode))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 140)
                            }
                            labeledField("Mon–Thu hours/day") {
                                TextField("4.5", value: $mondayThursdayHours, format: .number.precision(.fractionLength(0...2)))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 120)
                            }
                            labeledField("Friday hours") {
                                TextField("7.5", value: $fridayHours, format: .number.precision(.fractionLength(0...2)))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 120)
                            }

                            labeledField("Summer starts") {
                                DatePicker("", selection: $summerStart, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            labeledField("Summer ends") {
                                DatePicker("", selection: $summerEnd, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }

                        Divider()

                        metricRow("Hours / week", weeklyHours.formatted(.number.precision(.fractionLength(0...2))))
                        metricRow("Pay / week", MoneyFormat.string(weeklyPay))
                        metricRow("Summer weeks", summerWeeks.formatted(.number.precision(.fractionLength(0...1))))
                        metricRow("Planned summer income", MoneyFormat.string(previewIncome))
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("School-year runway") {
                    VStack(alignment: .leading, spacing: 16) {
                        labeledField("School year starts") {
                            DatePicker("", selection: $schoolYearStart, displayedComponents: .date)
                                .labelsHidden()
                        }
                        labeledField("Money should last until") {
                            DatePicker("", selection: $schoolYearEnd, displayedComponents: .date)
                                .labelsHidden()
                        }

                        Divider()

                        metricRow("School-year weeks", schoolWeeks.formatted(.number.precision(.fractionLength(0...1))))
                        Text("Overview uses Stocks + Savings as money locked away, then spreads the rest as a weekly/monthly school-year budget.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        metricRow(
                            "Rough safe weekly (if ~50% left for living)",
                            MoneyFormat.string(previewSafeWeekly)
                        )

                        Button("Save plan") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Income Plan")
        .onAppear(perform: load)
        .onChange(of: plan?.updatedAt) { _, _ in
            load()
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .frame(width: 180, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func load() {
        guard let plan else { return }
        hourlyWage = plan.hourlyWage
        mondayThursdayHours = plan.mondayThursdayHours > 0 ? plan.mondayThursdayHours : 4.5
        fridayHours = plan.fridayHours > 0 ? plan.fridayHours : 7.5
        summerStart = plan.summerStart
        summerEnd = plan.summerEnd
        schoolYearStart = plan.schoolYearStart
        schoolYearEnd = plan.schoolYearEnd
        useOverride = plan.usesOverride
        totalTargetOverride = plan.totalTargetOverride
    }

    private func save() {
        let target = plan ?? {
            let created = IncomePlan()
            modelContext.insert(created)
            return created
        }()

        target.hourlyWage = hourlyWage.clampedNonNegative
        target.mondayThursdayHours = mondayThursdayHours.clampedNonNegative
        target.fridayHours = fridayHours.clampedNonNegative
        target.summerStart = summerStart
        target.summerEnd = max(summerEnd, summerStart)
        target.schoolYearStart = schoolYearStart
        target.schoolYearEnd = max(schoolYearEnd, schoolYearStart)
        target.usesSchedule = !useOverride
        target.totalTargetOverride = useOverride ? totalTargetOverride.clampedNonNegative : 0
        target.syncDerivedFields()
        target.updatedAt = .now
        try? modelContext.save()
    }
}
