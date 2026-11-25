import SwiftData
import XCTest

final class SpendingTrendsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }()

    /// Monday, November 23, 2026.
    private var weekStart: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))! }

    private func buy(_ amount: Double, day: Int, _ category: SpendingCategory? = .food) -> SpendingTrends.Purchase {
        .init(date: calendar.date(byAdding: .day, value: day, to: weekStart)!, amount: amount, category: category)
    }

    private func trends(_ purchases: [SpendingTrends.Purchase], limit: Int = 12) -> SpendingTrends {
        SpendingTrends(purchases: purchases, currentWeekStart: weekStart, weekLimit: limit, weeklyAmount: 45, calendar: calendar)
    }

    func testNothingBoughtIsEmpty() { XCTAssertTrue(trends([]).isEmpty) }
    func testPurchasesLandInTheirWeek() { XCTAssertEqual(trends([buy(10, day: 1), buy(20, day: -1), buy(5, day: -7)]).weeks.map(\.spent), [25, 10]) }
    func testWeekStartsOnItsFirstMoment() { XCTAssertEqual(trends([buy(10, day: 0), buy(20, day: -1)]).weeks.map(\.spent), [20, 10]) }
    func testQuietWeeksShowAsZero() { XCTAssertEqual(trends([buy(10, day: -20), buy(5, day: 1)]).weeks.map(\.spent), [10, 0, 0, 5]) }
    func testStartsAtTheFirstPurchase() { XCTAssertEqual(trends([buy(10, day: -8)]).weeks.count, 3) }
    func testStopsAtTheLimit() { XCTAssertEqual(trends([buy(10, day: -100), buy(1, day: 0)], limit: 4).weeks.count, 4) }
    func testOlderPurchasesAreLeftOutOfTheTotal() { XCTAssertEqual(trends([buy(10, day: -100), buy(1, day: 0)], limit: 4).total, 1) }
    func testFuturePurchasesAreLeftOut() { XCTAssertEqual(trends([buy(10, day: 7), buy(1, day: 0)]).total, 1) }
    func testAverageSkipsTheUnfinishedWeek() { XCTAssertEqual(trends([buy(40, day: -8), buy(20, day: -1), buy(5, day: 0)]).averagePerWeek, 30) }
    func testAverageUsesThisWeekWhenItIsTheOnlyOne() { XCTAssertEqual(trends([buy(5, day: 0)]).averagePerWeek, 5) }
    func testCountsWeeksOver() { XCTAssertEqual(trends([buy(50, day: -8), buy(44, day: -1), buy(46, day: 0)]).weeksOver, 2) }
    func testExactlyTheWeeklyAmountIsNotOver() { XCTAssertEqual(trends([buy(45, day: -1)]).weeksOver, 0) }
    func testBiggestCategoryComesFirst() { XCTAssertEqual(trends([buy(5, day: 0, .fun), buy(9, day: 0, .food), buy(6, day: 1, .fun)]).categories.map(\.name), ["Fun", "Food"]) }
    func testPurchasesWithoutACategoryAreKept() { XCTAssertEqual(trends([buy(5, day: 0, nil)]).topCategory?.name, "No category") }
    func testCategoriesAddUpToTheTotal() {
        let result = trends([buy(5, day: 0, .fun), buy(9, day: -3, nil)])
        XCTAssertEqual(result.categories.reduce(0) { $0 + $1.amount }, result.total)
    }
    func testDaysFollowTheCalendar() { XCTAssertEqual(trends([buy(5, day: 0)]).days.map(\.weekday), [1, 2, 3, 4, 5, 6, 7]) }
    func testDayTotals() { XCTAssertEqual(trends([buy(5, day: 0), buy(7, day: -7), buy(1, day: 1)]).days.map(\.amount), [0, 12, 1, 0, 0, 0, 0]) }
}

@MainActor
final class SpendingCategoryTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([IncomePlan.self, BudgetCategory.self, MoneyEntry.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func entry(_ note: String, _ category: SpendingCategory?, daysAgo: Double = 0, kind: EntryKind = .spending) -> MoneyEntry {
        let entry = MoneyEntry(amount: 1, date: .now.addingTimeInterval(-daysAgo * 86_400), note: note, kind: kind, spendingCategory: category)
        container.mainContext.insert(entry)
        return entry
    }

    func testSuggestsTheLastCategoryForTheSameNote() {
        let entries = [entry("Movies", .other, daysAgo: 9), entry("Movies", .fun, daysAgo: 1)]
        XCTAssertEqual(SpendingCategory.suggested(for: " movies ", from: entries), .fun)
    }

    func testNoSuggestionForSomethingNew() { XCTAssertNil(SpendingCategory.suggested(for: "Shoes", from: [entry("Movies", .fun)])) }
    func testNoSuggestionForAnEmptyNote() { XCTAssertNil(SpendingCategory.suggested(for: "", from: [entry("", .fun)])) }
    func testOnlyPurchasesKeepACategory() { XCTAssertNil(entry("Shell", .food, kind: .gas).spendingCategory) }
}
