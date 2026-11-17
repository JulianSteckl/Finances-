import SwiftUI
import SwiftData

struct OverviewView: View {
    let plan: IncomePlan?
    let categories: [BudgetCategory]
    let entries: [MoneyEntry]

    private var totals: PlanTotals {
        FinanceMath.totals(plan: plan, entries: entries)
    }

    private var runway: RunwaySnapshot? {
        FinanceMath.runway(plan: plan, categories: categories, entries: entries)
    }

    private var remainingAllocation: Double {
        FinanceMath.remainingToAllocate(categories: categories, income: totals.plannedIncome)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SummaryCard(title: "Summer plan", value: MoneyFormat.string(totals.plannedIncome), footnote: planFootnote)
                    SummaryCard(title: "Earned so far", value: MoneyFormat.string(totals.actualIncome), footnote: "\(Int(totals.incomeProgress * 100))% of plan")
                    SummaryCard(title: "Spent so far", value: MoneyFormat.string(totals.actualSpending), footnote: "Net \(MoneyFormat.string(totals.netActual))")
                }

                if let runway {
                    runwaySection(runway)
                }

                allocationSection
                recentSection
            }
            .padding(28)
            .frame(maxWidth: 960, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Overview")
    }

    private var planFootnote: String {
        guard let plan else { return "Set your summer income plan" }
        if plan.usesOverride {
            return "Using total target override"
        }
        if plan.usesSchedule {
            return "\(plan.weeklyHoursFromSchedule.formatted(.number.precision(.fractionLength(0...1)))) hrs/wk × \(MoneyFormat.string(plan.hourlyWage)) × \(plan.summerWeeksComputed.formatted(.number.precision(.fractionLength(0...1)))) wks"
        }
        return "\(plan.hoursPerWeek.formatted()) hrs/wk × \(MoneyFormat.string(plan.hourlyWage)) × \(plan.weeksInSeason.formatted()) wks"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summer → school year")
                .font(.largeTitle.weight(.semibold))
            Text("Earn in the summer, then spend at a pace that lasts until school ends again.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runwaySection(_ runway: RunwaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("School-year runway")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(phaseLabel(runway.phase))
                    .foregroundStyle(.secondary)
                Text(runway.onTrack ? "On track" : "Over pace")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(runway.onTrack ? Color.green : Color.orange)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                SummaryCard(
                    title: "Living pool",
                    value: MoneyFormat.string(runway.livingPool),
                    footnote: "After \(MoneyFormat.string(runway.lockedAway)) locked in Stocks/Savings"
                )
                SummaryCard(
                    title: "Safe weekly",
                    value: MoneyFormat.string(runway.safeWeekly),
                    footnote: "\(MoneyFormat.string(runway.safeMonthly))/mo over \(runway.schoolYearWeeks.formatted(.number.precision(.fractionLength(0...1)))) weeks"
                )
                SummaryCard(
                    title: runway.phase == .schoolYear ? "Suggested now" : "Weekly pay",
                    value: MoneyFormat.string(
                        runway.phase == .schoolYear ? runway.suggestedWeeklyNow : runway.weeklyPay
                    ),
                    footnote: runway.phase == .schoolYear
                        ? "Based on \(MoneyFormat.string(runway.remainingCash)) left ÷ \(runway.weeksLeftInSchoolYear.formatted(.number.precision(.fractionLength(0...1)))) weeks left"
                        : "\(runway.weeklyHours.formatted(.number.precision(.fractionLength(0...1)))) hrs × wage"
                )
            }

            if runway.phase == .schoolYear && runway.spentPerWeekSoFar > 0 {
                Text("You’re averaging \(MoneyFormat.string(runway.spentPerWeekSoFar))/week since school started (target \(MoneyFormat.string(runway.safeWeekly))).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func phaseLabel(_ phase: RunwaySnapshot.Phase) -> String {
        switch phase {
        case .summer: "Summer earning"
        case .schoolYear: "School year"
        case .between: "Between seasons"
        }
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Allocation snapshot")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(remainingLabel)
                    .foregroundStyle(remainingAllocation < -0.5 ? .red : .secondary)
            }

            if categories.isEmpty {
                EmptyHint(text: "Add categories in Allocations to split your planned income.")
            } else {
                VStack(spacing: 10) {
                    ForEach(categories) { category in
                        let planned = category.plannedAmount(forIncome: totals.plannedIncome)
                        let spent = FinanceMath.spent(in: category, entries: entries)
                        AllocationProgressRow(
                            category: category,
                            planned: planned,
                            spent: spent
                        )
                    }
                }
            }
        }
    }

    private var remainingLabel: String {
        if abs(remainingAllocation) < 0.5 {
            return "Fully allocated"
        }
        if remainingAllocation > 0 {
            return "\(MoneyFormat.string(remainingAllocation)) left for school-year living"
        }
        return "\(MoneyFormat.string(abs(remainingAllocation))) over-allocated"
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity")
                .font(.title2.weight(.semibold))

            if entries.isEmpty {
                EmptyHint(text: "No paychecks or spending yet. Log your first entry in Tracking.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(6))) { entry in
                        EntryRow(entry: entry)
                        if entry.persistentModelID != entries.prefix(6).last?.persistentModelID {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
            Text(footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AllocationProgressRow: View {
    let category: BudgetCategory
    let planned: Double
    let spent: Double

    private var progress: Double {
        guard planned > 0 else { return spent > 0 ? 1 : 0 }
        return min(1, spent / planned)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(category.name, systemImage: category.symbolName)
                Spacer()
                Text("\(MoneyFormat.string(spent)) / \(MoneyFormat.string(planned))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(category.color)
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EntryRow: View {
    let entry: MoneyEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .foregroundStyle(entry.isIncome ? Color.green : Color.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? entry.kind.label : entry.note)
                Text(entry.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text((entry.isIncome ? "+" : "−") + MoneyFormat.string(entry.amount))
                .monospacedDigit()
                .foregroundStyle(entry.isIncome ? Color.green : Color.primary)
        }
        .padding(.vertical, 10)
    }
}
