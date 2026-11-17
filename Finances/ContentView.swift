import SwiftUI
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case income
    case allocations
    case tracking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .income: "Income Plan"
        case .allocations: "Allocations"
        case .tracking: "Tracking"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .income: "briefcase"
        case .allocations: "chart.pie"
        case .tracking: "list.bullet.rectangle"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [IncomePlan]
    @Query(sort: \BudgetCategory.sortOrder) private var categories: [BudgetCategory]
    @Query(sort: \MoneyEntry.date, order: .reverse) private var entries: [MoneyEntry]

    @State private var section: AppSection = .overview

    private var plan: IncomePlan? { plans.first }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(AppSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .navigationTitle("Finances")
        } detail: {
            Group {
                switch section {
                case .overview:
                    OverviewView(plan: plan, categories: categories, entries: entries)
                case .income:
                    IncomePlanView(plan: plan)
                case .allocations:
                    AllocationsView(plan: plan, categories: categories)
                case .tracking:
                    TrackingView(categories: categories, entries: entries)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            SeedData.ensureDefaults(in: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [IncomePlan.self, BudgetCategory.self, MoneyEntry.self], inMemory: true)
}
