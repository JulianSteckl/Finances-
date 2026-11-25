import Foundation
import SwiftData

enum PayFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case semimonthly
    case monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .semimonthly: "Twice a month"
        case .monthly: "Monthly"
        }
    }

    /// Number of paychecks received per week of work, on average.
    var paychecksPerWeek: Double {
        switch self {
        case .weekly: 1
        case .biweekly: 0.5
        case .semimonthly: 24.0 / 52.0
        case .monthly: 12.0 / 52.0
        }
    }
}

@Model
final class IncomePlan {
    var hoursPerWeek: Double
    var hourlyWage: Double
    var weeksInSeason: Double
    /// Optional override. When > 0, this becomes the planned income target.
    var totalTargetOverride: Double
    var updatedAt: Date

    // Season dates. When `usesSeasonDates` is on, `weeksInSeason` is derived from these on save.
    var usesSeasonDates: Bool = false
    var seasonStart: Date = Date.now
    var seasonEnd: Date = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: .now) ?? .now
    var payFrequencyRaw: String = PayFrequency.biweekly.rawValue

    // Overtime and extras.
    var overtimeHoursPerWeek: Double = 0
    var overtimeMultiplier: Double = 1.5
    var tipsPerWeek: Double = 0
    /// One-time extras for the whole season (bonuses, signing pay, etc.).
    var oneTimeBonuses: Double = 0

    // Year budget: what happens to the money once it's earned.
    var allowancePerWeek: Double = 15
    var spendingPerWeek: Double = 45
    var gasPerTwoWeeks: Double = 50
    var savingsGoal: Double = 1600
    var startingMoney: Double = 0
    /// Share of pay withheld for taxes, 0...1.
    var taxRate: Double = 0
    /// Yearly growth, 0...1.
    var stockReturn: Double = 0.07
    var savingsReturn: Double = 0.02
    /// First day of the summer job when it's typed in on its own, without an end date.
    var jobStart: Date?

    init(
        hoursPerWeek: Double = 29.5,
        hourlyWage: Double = 20,
        weeksInSeason: Double = 13,
        totalTargetOverride: Double = 0,
        updatedAt: Date = .now
    ) {
        self.hoursPerWeek = hoursPerWeek
        self.hourlyWage = hourlyWage
        self.weeksInSeason = weeksInSeason
        self.totalTargetOverride = totalTargetOverride
        self.updatedAt = updatedAt
    }

    var payFrequency: PayFrequency {
        get { PayFrequency(rawValue: payFrequencyRaw) ?? .biweekly }
        set { payFrequencyRaw = newValue.rawValue }
    }

    var breakdown: IncomeBreakdown {
        IncomeBreakdown(
            hoursPerWeek: hoursPerWeek,
            hourlyWage: hourlyWage,
            weeksInSeason: weeksInSeason,
            overtimeHoursPerWeek: overtimeHoursPerWeek,
            overtimeMultiplier: overtimeMultiplier,
            tipsPerWeek: tipsPerWeek,
            oneTimeBonuses: oneTimeBonuses,
            totalTargetOverride: totalTargetOverride,
            payFrequency: payFrequency
        )
    }

    var computedFromHours: Double {
        breakdown.computedTotal
    }

    var plannedIncome: Double {
        breakdown.plannedIncome
    }

    var usesOverride: Bool {
        totalTargetOverride > 0
    }

    /// The plan's numbers for the year math.
    var inputs: PlanInputs {
        PlanInputs(
            hourlyWage: hourlyWage,
            hoursPerWeek: hoursPerWeek,
            weeksOfWork: weeksInSeason,
            extraPerWeek: overtimeHoursPerWeek * hourlyWage * overtimeMultiplier + tipsPerWeek,
            oneTimeBonuses: oneTimeBonuses,
            jobTotalOverride: totalTargetOverride,
            taxRate: taxRate,
            allowancePerWeek: allowancePerWeek,
            spendingPerWeek: spendingPerWeek,
            gasPerTwoWeeks: gasPerTwoWeeks,
            savingsGoal: savingsGoal,
            startingMoney: startingMoney,
            stockReturn: stockReturn,
            savingsReturn: savingsReturn
        )
    }

    var yearPlan: YearPlan { YearPlan(inputs) }

    /// Saves the what-if values the Year plan screen lets you change.
    func applyWhatIf(_ draft: PlanInputs) {
        hourlyWage = draft.hourlyWage
        hoursPerWeek = draft.hoursPerWeek
        if draft.weeksOfWork != weeksInSeason {
            // Typed-in weeks replace the date range, or the dates would recalculate it on the next save.
            weeksInSeason = draft.weeksOfWork
            if usesSeasonDates { jobStart = seasonStart }
            usesSeasonDates = false
        }
        spendingPerWeek = draft.spendingPerWeek
        savingsGoal = draft.savingsGoal
        stockReturn = draft.stockReturn
        updatedAt = .now
    }

    /// First day of the summer job, if it's known. Pay before it counts as odd jobs, not as weeks of work.
    var jobStartDate: Date? {
        usesSeasonDates ? seasonStart : jobStart
    }
}

/// Pure calculation of planned income and its derived figures, shared by the model and the editor preview.
struct IncomeBreakdown {
    var hoursPerWeek: Double
    var hourlyWage: Double
    var weeksInSeason: Double
    var overtimeHoursPerWeek: Double
    var overtimeMultiplier: Double
    var tipsPerWeek: Double
    var oneTimeBonuses: Double
    var totalTargetOverride: Double
    var payFrequency: PayFrequency

    static func weeks(from start: Date, to end: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        // Count both the start and end day so a Mon–Sun range is exactly one week.
        return max(0, Double(days + 1) / 7)
    }

    var regularPay: Double { hoursPerWeek * hourlyWage * weeksInSeason }
    var overtimePay: Double { overtimeHoursPerWeek * hourlyWage * overtimeMultiplier * weeksInSeason }
    var tipsTotal: Double { tipsPerWeek * weeksInSeason }

    var computedTotal: Double { regularPay + overtimePay + tipsTotal + oneTimeBonuses }

    var usesOverride: Bool { totalTargetOverride > 0 }
    var plannedIncome: Double { usesOverride ? totalTargetOverride : computedTotal }

    var totalHours: Double { (hoursPerWeek + overtimeHoursPerWeek) * weeksInSeason }

    var perWeek: Double { weeksInSeason > 0 ? plannedIncome / weeksInSeason : 0 }
    var perMonth: Double { perWeek * 52 / 12 }

    var paychecks: Double { weeksInSeason * payFrequency.paychecksPerWeek }
    var perPaycheck: Double { paychecks > 0 ? plannedIncome / paychecks : 0 }

    /// Planned income divided by every hour worked, including tips and bonuses.
    var effectiveHourly: Double { totalHours > 0 ? plannedIncome / totalHours : 0 }
}
