import Foundation
import SwiftData

enum SeedData {
    static func ensureDefaults(in context: ModelContext) {
        let categoryDescriptor = FetchDescriptor<BudgetCategory>()
        let existingCategories = (try? context.fetch(categoryDescriptor)) ?? []

        if existingCategories.isEmpty {
            // Leave a large unallocated slice for school-year living (shown as runway).
            let starters: [(String, AllocationMode, Double, String, String)] = [
                ("Stocks", .percent, 25, "chart.line.uptrend.xyaxis", "#2F6F5E"),
                ("Savings", .percent, 25, "building.columns.fill", "#3B6EA5"),
                ("Gas", .percent, 10, "fuelpump.fill", "#C47A2C")
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
        } else if let plan = existingPlans.first {
            // Soft-upgrade older plans that never had schedule fields populated meaningfully.
            if plan.hourlyWage <= 0 { plan.hourlyWage = 20 }
            if plan.mondayThursdayHours <= 0 { plan.mondayThursdayHours = 4.5 }
            if plan.fridayHours <= 0 { plan.fridayHours = 7.5 }
            plan.syncDerivedFields()
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

struct RunwaySnapshot {
    let weeklyHours: Double
    let weeklyPay: Double
    let summerWeeks: Double
    let schoolYearWeeks: Double
    let plannedIncome: Double
    /// Stocks + Savings planned amounts (money set aside, not for daily living).
    let lockedAway: Double
    /// What should fund school-year living (and gas/flex).
    let livingPool: Double
    let safeWeekly: Double
    let safeMonthly: Double
    let weeksLeftInSchoolYear: Double
    let remainingCash: Double
    let suggestedWeeklyNow: Double
    let spentPerWeekSoFar: Double
    let onTrack: Bool
    let phase: Phase

    enum Phase {
        case summer
        case schoolYear
        case between
    }
}

enum FinanceMath {
    static let longTermNames: Set<String> = ["stocks", "savings"]

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

    static func lockedAway(categories: [BudgetCategory], income: Double) -> Double {
        categories
            .filter { longTermNames.contains($0.name.lowercased()) }
            .reduce(0) { $0 + $1.plannedAmount(forIncome: income) }
    }

    static func runway(
        plan: IncomePlan?,
        categories: [BudgetCategory],
        entries: [MoneyEntry],
        now: Date = .now
    ) -> RunwaySnapshot? {
        guard let plan else { return nil }

        let totals = totals(plan: plan, entries: entries)
        let weeklyHours = plan.usesSchedule ? plan.weeklyHoursFromSchedule : plan.hoursPerWeek
        let weeklyPay = weeklyHours * plan.hourlyWage
        let summerWeeks = plan.usesSchedule ? plan.summerWeeksComputed : plan.weeksInSeason
        let schoolWeeks = max(plan.schoolYearWeeksComputed, 0.1)
        let locked = lockedAway(categories: categories, income: totals.plannedIncome)
        let living = max(0, totals.plannedIncome - locked)
        let safeWeekly = living / schoolWeeks
        let safeMonthly = safeWeekly * (52.0 / 12.0)

        let weeksLeft = max(
            SeasonCalendar.weeks(from: min(now, plan.schoolYearEnd), to: plan.schoolYearEnd),
            0.1
        )
        let remainingCash = max(0, totals.netActual)
        let suggestedNow = remainingCash / weeksLeft

        let schoolSpendEntries = entries.filter { !$0.isIncome && $0.date >= plan.schoolYearStart }
        let spendElapsedWeeks = max(
            SeasonCalendar.weeks(from: plan.schoolYearStart, to: max(now, plan.schoolYearStart)),
            1.0 / 7.0
        )
        let spentInSchoolYear = schoolSpendEntries.reduce(0) { $0 + $1.amount }
        let spentPerWeek = spentInSchoolYear / spendElapsedWeeks

        let phase: RunwaySnapshot.Phase
        if now >= plan.summerStart && now <= plan.summerEnd {
            phase = .summer
        } else if now >= plan.schoolYearStart && now <= plan.schoolYearEnd {
            phase = .schoolYear
        } else {
            phase = .between
        }

        let onTrack: Bool
        if phase == .schoolYear && spentInSchoolYear > 0 {
            onTrack = spentPerWeek <= safeWeekly * 1.08
        } else {
            onTrack = remainingCash >= 0
        }

        return RunwaySnapshot(
            weeklyHours: weeklyHours,
            weeklyPay: weeklyPay,
            summerWeeks: summerWeeks,
            schoolYearWeeks: schoolWeeks,
            plannedIncome: totals.plannedIncome,
            lockedAway: locked,
            livingPool: living,
            safeWeekly: safeWeekly,
            safeMonthly: safeMonthly,
            weeksLeftInSchoolYear: weeksLeft,
            remainingCash: remainingCash,
            suggestedWeeklyNow: suggestedNow,
            spentPerWeekSoFar: spentPerWeek,
            onTrack: onTrack,
            phase: phase
        )
    }
}
