import Foundation
import SwiftData

@Model
final class IncomePlan {
    var hoursPerWeek: Double
    var hourlyWage: Double
    var weeksInSeason: Double
    /// Optional override. When > 0, this becomes the planned income target.
    var totalTargetOverride: Double
    var updatedAt: Date

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

    var computedFromHours: Double {
        hoursPerWeek * hourlyWage * weeksInSeason
    }

    var plannedIncome: Double {
        totalTargetOverride > 0 ? totalTargetOverride : computedFromHours
    }

    var usesOverride: Bool {
        totalTargetOverride > 0
    }
}
