import Foundation

enum SeasonCalendar {
    /// Summer work window and the following school-year runway for a reference date.
    /// School ends May 21; school returns ~Aug 17.
    static func season(for reference: Date = .now, calendar: Calendar = .current) -> (
        summerStart: Date,
        summerEnd: Date,
        schoolYearStart: Date,
        schoolYearEnd: Date
    ) {
        let year = calendar.component(.year, from: reference)
        let thisSummerStart = date(year: year, month: 5, day: 21, calendar: calendar)
        let thisSummerEnd = date(year: year, month: 8, day: 17, calendar: calendar)

        // After summer ends, plan the next summer / following school year.
        if reference > thisSummerEnd {
            let nextYear = year + 1
            return (
                summerStart: date(year: nextYear, month: 5, day: 21, calendar: calendar),
                summerEnd: date(year: nextYear, month: 8, day: 17, calendar: calendar),
                schoolYearStart: date(year: nextYear, month: 8, day: 17, calendar: calendar),
                schoolYearEnd: date(year: nextYear + 1, month: 5, day: 21, calendar: calendar)
            )
        }

        return (
            summerStart: thisSummerStart,
            summerEnd: thisSummerEnd,
            schoolYearStart: thisSummerEnd,
            schoolYearEnd: date(year: year + 1, month: 5, day: 21, calendar: calendar)
        )
    }

    static func weeks(from start: Date, to end: Date) -> Double {
        let days = Calendar.current.dateComponents([.day], from: start.startOfDay, to: end.startOfDay).day ?? 0
        return max(0, Double(days) / 7.0)
    }

    static func daysRemaining(until end: Date, from reference: Date = .now) -> Int {
        let days = Calendar.current.dateComponents([.day], from: reference.startOfDay, to: end.startOfDay).day ?? 0
        return max(0, days)
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
