import Foundation
import SwiftData

/// Logs the weekly allowance by itself on payday, including paydays missed while the app was closed.
enum AutoAllowance {
    private static let daysPerWeek = 7
    /// An allowance logged by hand this close to a payday counts as that week's.
    private static let sameWeekDays = 3
    private static let noonHour = 12

    /// Every `weekday` (1 = Sunday) after `after`, up to and including the day of `through`.
    static func paydays(weekday: Int, after: Date, through: Date, calendar: Calendar = .current) -> [Date] {
        let lastDay = calendar.startOfDay(for: through)
        guard var day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: after)), (1...daysPerWeek).contains(weekday) else { return [] }
        let wait = (weekday - calendar.component(.weekday, from: day) + daysPerWeek) % daysPerWeek
        day = calendar.date(byAdding: .day, value: wait, to: day) ?? day
        var result: [Date] = []
        while day <= lastDay {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: daysPerWeek, to: day) else { break }
            day = next
        }
        return result
    }

    /// Paydays that don't already have an allowance logged around them.
    static func missing(_ paydays: [Date], logged: [Date], calendar: Calendar = .current) -> [Date] {
        paydays.filter { payday in
            !logged.contains { date in
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: payday), to: calendar.startOfDay(for: date)).day ?? .max
                return abs(days) <= sameWeekDays
            }
        }
    }

    /// Logs whatever is due. Each day is only looked at once, so deleting an entry doesn't bring it back.
    @MainActor
    static func run(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        guard let plan = try? context.fetch(FetchDescriptor<IncomePlan>()).first,
              let weekday = plan.allowanceWeekday, let loggedThrough = plan.allowanceLoggedThrough,
              calendar.startOfDay(for: loggedThrough) < calendar.startOfDay(for: now),
              let entries = try? context.fetch(FetchDescriptor<MoneyEntry>()) else { return }

        let due = missing(
            paydays(weekday: weekday, after: loggedThrough, through: now, calendar: calendar),
            logged: entries.filter { $0.kind == .allowance }.map(\.date), calendar: calendar
        )
        if plan.allowancePerWeek > 0 {
            for payday in due {
                let noon = calendar.date(byAdding: .hour, value: noonHour, to: payday) ?? payday
                context.insert(MoneyEntry(amount: plan.allowancePerWeek, date: min(noon, now), kind: .allowance))
            }
        }
        plan.allowanceLoggedThrough = calendar.startOfDay(for: now)
        context.saveChanges()
    }
}
