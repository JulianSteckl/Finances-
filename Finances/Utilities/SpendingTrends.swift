import Foundation

/// Purchases grouped by week, category and day of the week.
struct SpendingTrends {
    struct Purchase {
        let date: Date
        let amount: Double
        let category: SpendingCategory?
    }

    struct Week: Identifiable {
        let start: Date
        let spent: Double
        let isCurrent: Bool
        var id: Date { start }
    }

    struct CategoryTotal: Identifiable {
        let category: SpendingCategory?
        let amount: Double
        var name: String { category?.name ?? SpendingCategory.missingName }
        var id: String { category?.rawValue ?? "" }
    }

    struct DayTotal: Identifiable {
        /// 1 = Sunday.
        let weekday: Int
        let amount: Double
        var id: Int { weekday }
    }

    /// Oldest first, ending with this week. Starts no earlier than the first purchase.
    let weeks: [Week]
    let total: Double
    /// Over finished weeks, or this week when it's the only one.
    let averagePerWeek: Double
    /// Weeks that went over the weekly amount, this week included once it has.
    let weeksOver: Int
    /// Biggest first.
    let categories: [CategoryTotal]
    /// In the calendar's own order, all seven days.
    let days: [DayTotal]

    var isEmpty: Bool { total <= 0 }
    var topCategory: CategoryTotal? { categories.first }

    private static let daysPerWeek = 7
    private static let halfCent = 0.005

    /// `currentWeekStart` keeps these weeks lined up with the spending weeks on the Overview.
    init(purchases: [Purchase], currentWeekStart: Date, weekLimit: Int, weeklyAmount: Double, calendar: Calendar = .current) {
        func weekStart(_ weeksAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -weeksAgo * Self.daysPerWeek, to: currentWeekStart) ?? currentWeekStart
        }
        let end = weekStart(-1)
        let past = purchases.filter { $0.date < end }
        var count = 1
        if let first = past.map(\.date).min() {
            while count < weekLimit, first < weekStart(count - 1) { count += 1 }
        }
        let inRange = past.filter { $0.date >= weekStart(count - 1) }

        weeks = (0..<count).reversed().map { weeksAgo in
            let start = weekStart(weeksAgo), finish = weekStart(weeksAgo - 1)
            let spent = inRange.filter { $0.date >= start && $0.date < finish }.reduce(0) { $0 + $1.amount }
            return Week(start: start, spent: spent, isCurrent: weeksAgo == 0)
        }
        total = inRange.reduce(0) { $0 + $1.amount }
        let finished = weeks.filter { !$0.isCurrent }
        averagePerWeek = finished.isEmpty ? total : finished.reduce(0) { $0 + $1.spent } / Double(finished.count)
        weeksOver = weeks.filter { $0.spent > weeklyAmount + Self.halfCent }.count
        categories = Dictionary(grouping: inRange, by: \.category)
            .map { CategoryTotal(category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { ($0.amount, $1.name) > ($1.amount, $0.name) }
        let byDay = Dictionary(grouping: inRange) { calendar.component(.weekday, from: $0.date) }
        days = (0..<Self.daysPerWeek).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % Self.daysPerWeek + 1
            return DayTotal(weekday: weekday, amount: (byDay[weekday] ?? []).reduce(0) { $0 + $1.amount })
        }
    }
}
