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
    @Query(sort: \MoneyEntry.date, order: .reverse) private var entries: [MoneyEntry]

    @State private var section: AppSection = .overview

    private var plan: IncomePlan? { plans.first }
    private var ledger: Ledger { Ledger(entries: entries) }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Theme.ink)
        .onAppear {
            SeedData.ensureDefaults(in: modelContext)
        }
    }

    private var sidebar: some View {
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
                    }
                    .selectionDisabled()
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        .navigationTitle("Financial")
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .overview:
            OverviewView(plan: plan, entries: entries) { section = .paychecks }
        case .paychecks:
            PaychecksView(plan: plan, entries: entries)
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
