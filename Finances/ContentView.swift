import SwiftUI
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case paychecks
    case yearPlan
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .paychecks: "Paychecks & log"
        case .yearPlan: "Year plan"
        case .settings: "Plan settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .paychecks: "banknote"
        case .yearPlan: "chart.line.uptrend.xyaxis"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [IncomePlan]
    // Changes to the log animate every number, bar and row that depends on them.
    @Query(sort: \MoneyEntry.date, order: .reverse, animation: Motion.smooth) private var entries: [MoneyEntry]

    @State private var section: AppSection = .overview

    private var plan: IncomePlan? { plans.first }

    var body: some View {
        // Built once per change to the log and shared by the sidebar and every screen.
        let ledger = Ledger(entries: entries)
        return NavigationSplitView {
            sidebar(ledger)
        } detail: {
            detail(ledger)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .hidingToolbarTitle()
        }
        .tint(Theme.ink)
        .onAppear {
            SeedData.ensureDefaults(in: modelContext)
            AutoAllowance.run(in: modelContext)
        }
    }

    private func sidebar(_ ledger: Ledger) -> some View {
        List(selection: $section) {
            Section {
                ForEach(AppSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            Section("Buckets") {
                ForEach(Bucket.allCases) { bucket in
                    HStack(spacing: 10) {
                        BucketDot(bucket: bucket)
                        Text(bucket.name)
                        Spacer()
                        Text(MoneyFormat.whole(ledger.balance(of: bucket)))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .animatedNumber(ledger.balance(of: bucket))
                    }
                    .selectionDisabled()
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        .navigationTitle("Financial")
    }

    @ViewBuilder
    private func detail(_ ledger: Ledger) -> some View {
        switch section {
        case .overview:
            OverviewView(plan: plan, ledger: ledger) { section = .paychecks }
        case .paychecks:
            PaychecksView(plan: plan, ledger: ledger)
        case .yearPlan:
            YearPlanView(plan: plan)
        case .settings:
            IncomePlanView(plan: plan)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [IncomePlan.self, BudgetCategory.self, MoneyEntry.self], inMemory: true)
}
