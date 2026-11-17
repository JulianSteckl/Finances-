import SwiftUI
import SwiftData

struct OverviewView: View {
    let plan: IncomePlan?
    let categories: [BudgetCategory]
    let entries: [MoneyEntry]

    private var totals: PlanTotals {
        FinanceMath.totals(plan: plan, entries: entries)
    }

    private var remainingAllocation: Double {
        FinanceMath.remainingToAllocate(categories: categories, income: totals.plannedIncome)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SummaryCard(title: "Planned income", value: MoneyFormat.string(totals.plannedIncome), footnote: planFootnote)
                    SummaryCard(title: "Earned so far", value: MoneyFormat.string(totals.actualIncome), footnote: "\(Int(totals.incomeProgress * 100))% of plan")
                    SummaryCard(title: "Spent so far", value: MoneyFormat.string(totals.actualSpending), footnote: "Net \(MoneyFormat.string(totals.netActual))")
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
        return "\(plan.hoursPerWeek.formatted()) hrs/wk × \(MoneyFormat.string(plan.hourlyWage)) × \(plan.weeksInSeason.formatted()) wks"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summer money")
                .font(.largeTitle.weight(.semibold))
            Text("Plan your earnings, split them into buckets, then track paychecks and spending as the season goes.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            return "\(MoneyFormat.string(remainingAllocation)) left to allocate"
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
                .lineLimit(2)
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
