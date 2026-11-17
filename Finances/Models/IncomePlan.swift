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

    init(
        hoursPerWeek: Double = 30,
        hourlyWage: Double = 15,
        weeksInSeason: Double = 12,
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
