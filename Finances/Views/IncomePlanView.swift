import SwiftUI
import SwiftData

struct IncomePlanView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?

    @State private var hoursPerWeek: Double = 30
    @State private var hourlyWage: Double = 15
    @State private var weeksInSeason: Double = 12
    @State private var useOverride = false
    @State private var totalTargetOverride: Double = 0

    private var previewIncome: Double {
        if useOverride {
            return totalTargetOverride.clampedNonNegative
        }
        return hoursPerWeek * hourlyWage * weeksInSeason
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Income plan")
                        .font(.largeTitle.weight(.semibold))
                    Text("Estimate what you expect to earn this summer from hours and wage, or set a total target.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Expected earnings") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Use a total target instead of hours × wage", isOn: $useOverride)

                        if useOverride {
                            labeledField("Total summer target") {
                                TextField("0", value: $totalTargetOverride, format: .currency(code: currencyCode))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 220)
                            }
                        } else {
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
                            labeledField("Weeks in season") {
                                TextField("12", value: $weeksInSeason, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 120)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Planned income")
                                .font(.headline)
                            Spacer()
                            Text(MoneyFormat.string(previewIncome))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                        }

                        Button("Save plan") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("How it’s used") {
                    Text("Allocations split this planned income into buckets. Tracking compares actual paychecks and spending against the plan.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
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
                .frame(width: 160, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func load() {
        guard let plan else { return }
        hoursPerWeek = plan.hoursPerWeek
        hourlyWage = plan.hourlyWage
        weeksInSeason = plan.weeksInSeason
        useOverride = plan.usesOverride
        totalTargetOverride = plan.totalTargetOverride
    }

    private func save() {
        let target = plan ?? {
            let created = IncomePlan()
            modelContext.insert(created)
            return created
        }()

        target.hoursPerWeek = hoursPerWeek.clampedNonNegative
        target.hourlyWage = hourlyWage.clampedNonNegative
        target.weeksInSeason = weeksInSeason.clampedNonNegative
        target.totalTargetOverride = useOverride ? totalTargetOverride.clampedNonNegative : 0
        target.updatedAt = .now
        try? modelContext.save()
    }
}
