import Foundation
import SwiftData

@Model
final class IncomePlan {
    /// Kept in sync with the weekly schedule for math callers.
    var hoursPerWeek: Double = 25.5
    var hourlyWage: Double = 20
    /// Derived from summer start/end when using the schedule.
    var weeksInSeason: Double = 12
    /// Optional override. When > 0, this becomes the planned income target.
    var totalTargetOverride: Double = 0
    var updatedAt: Date = .now

    /// Typical hours each Monday–Thursday.
    var mondayThursdayHours: Double = 4.5
    /// Typical Friday hours (longer day).
    var fridayHours: Double = 7.5
    /// When true, planned income comes from schedule × wage × summer length.
    var usesSchedule: Bool = true

    var summerStart: Date = SeasonCalendar.season().summerStart
    var summerEnd: Date = SeasonCalendar.season().summerEnd
    /// First day the summer pile needs to last (usually school return).
    var schoolYearStart: Date = SeasonCalendar.season().schoolYearStart
    /// Last day the pile should last (usually next year’s last school day).
    var schoolYearEnd: Date = SeasonCalendar.season().schoolYearEnd

    init(
        hourlyWage: Double = 20,
        mondayThursdayHours: Double = 4.5,
        fridayHours: Double = 7.5,
        totalTargetOverride: Double = 0,
        usesSchedule: Bool = true,
        summerStart: Date? = nil,
        summerEnd: Date? = nil,
        schoolYearStart: Date? = nil,
        schoolYearEnd: Date? = nil,
        updatedAt: Date = .now
    ) {
        let season = SeasonCalendar.season(for: updatedAt)
        self.hourlyWage = hourlyWage
        self.mondayThursdayHours = mondayThursdayHours
        self.fridayHours = fridayHours
        self.usesSchedule = usesSchedule
        self.summerStart = summerStart ?? season.summerStart
        self.summerEnd = summerEnd ?? season.summerEnd
        self.schoolYearStart = schoolYearStart ?? season.schoolYearStart
        self.schoolYearEnd = schoolYearEnd ?? season.schoolYearEnd
        self.totalTargetOverride = totalTargetOverride
        self.updatedAt = updatedAt
        self.hoursPerWeek = (mondayThursdayHours * 4) + fridayHours
        self.weeksInSeason = SeasonCalendar.weeks(
            from: self.summerStart,
            to: self.summerEnd
        )
    }

    var weeklyHoursFromSchedule: Double {
        (mondayThursdayHours * 4) + fridayHours
    }

    var weeklyPayFromSchedule: Double {
        weeklyHoursFromSchedule * hourlyWage
    }

    var summerWeeksComputed: Double {
        SeasonCalendar.weeks(from: summerStart, to: summerEnd)
    }

    var schoolYearWeeksComputed: Double {
        SeasonCalendar.weeks(from: schoolYearStart, to: schoolYearEnd)
    }

    var computedFromSchedule: Double {
        weeklyPayFromSchedule * summerWeeksComputed
    }

    var computedFromHours: Double {
        hoursPerWeek * hourlyWage * weeksInSeason
    }

    var plannedIncome: Double {
        if totalTargetOverride > 0 { return totalTargetOverride }
        if usesSchedule { return computedFromSchedule }
        return computedFromHours
    }

    var usesOverride: Bool {
        totalTargetOverride > 0
    }

    func syncDerivedFields() {
        hoursPerWeek = weeklyHoursFromSchedule
        weeksInSeason = summerWeeksComputed
    }
}
