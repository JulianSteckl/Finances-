import Foundation
import SwiftData

enum SeedData {
    static func ensureDefaults(in context: ModelContext) {
        let categoryDescriptor = FetchDescriptor<BudgetCategory>()
        let existingCategories = (try? context.fetch(categoryDescriptor)) ?? []

        if existingCategories.isEmpty {
            let starters: [(String, AllocationMode, Double, String, String)] = [
                ("Stocks", .percent, 40, "chart.line.uptrend.xyaxis", "#2F6F5E"),
                ("Savings", .percent, 40, "building.columns.fill", "#3B6EA5"),
                ("Gas", .percent, 20, "fuelpump.fill", "#C47A2C")
            ]

            for (index, item) in starters.enumerated() {
                let category = BudgetCategory(
                    name: item.0,
                    mode: item.1,
                    allocationValue: item.2,
                    sortOrder: index,
                    symbolName: item.3,
                    colorHex: item.4
                )
                context.insert(category)
            }
        }

        let planDescriptor = FetchDescriptor<IncomePlan>()
        let existingPlans = (try? context.fetch(planDescriptor)) ?? []
        if existingPlans.isEmpty {
            context.insert(IncomePlan())
        }

        try? context.save()
    }
}

struct PlanTotals {
    let plannedIncome: Double
    let actualIncome: Double
    let actualSpending: Double

    var remainingToEarn: Double { max(0, plannedIncome - actualIncome) }
    var netActual: Double { actualIncome - actualSpending }
    var incomeProgress: Double {
        guard plannedIncome > 0 else { return 0 }
        return min(1, actualIncome / plannedIncome)
    }
}

enum FinanceMath {
    static func totals(plan: IncomePlan?, entries: [MoneyEntry]) -> PlanTotals {
        let planned = plan?.plannedIncome ?? 0
        let income = entries.filter(\.isIncome).reduce(0) { $0 + $1.amount }
        let spending = entries.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
        return PlanTotals(plannedIncome: planned, actualIncome: income, actualSpending: spending)
    }

    static func allocatedTotal(categories: [BudgetCategory], income: Double) -> Double {
        categories.reduce(0) { $0 + $1.plannedAmount(forIncome: income) }
    }

    static func remainingToAllocate(categories: [BudgetCategory], income: Double) -> Double {
        income - allocatedTotal(categories: categories, income: income)
    }

    static func spent(in category: BudgetCategory, entries: [MoneyEntry]) -> Double {
        entries
            .filter { !$0.isIncome && $0.category?.persistentModelID == category.persistentModelID }
            .reduce(0) { $0 + $1.amount }
    }
}
