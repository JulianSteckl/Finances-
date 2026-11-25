import SwiftData
import XCTest

@MainActor
final class AutoAllowanceTests: XCTestCase {
    private static let friday = 6
    private let calendar = Calendar.current
    private var container: ModelContainer!

    /// Friday, November 6, 2026 at 9 in the morning.
    private var payday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: payday)! }

    override func setUpWithError() throws {
        let schema = Schema([IncomePlan.self, BudgetCategory.self, MoneyEntry.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    @discardableResult
    private func plan(turnedOn date: Date) -> IncomePlan {
        let plan = IncomePlan()
        container.mainContext.insert(plan)
        plan.setAllowance(weekday: Self.friday, now: date)
        return plan
    }

    private func run(_ date: Date) { AutoAllowance.run(in: container.mainContext, now: date) }

    private func allowances() throws -> [MoneyEntry] {
        try container.mainContext.fetch(FetchDescriptor<MoneyEntry>(sortBy: [SortDescriptor(\.date)]))
    }

    func testLogsOnPayday() throws {
        plan(turnedOn: day(-2)); run(payday)
        XCTAssertEqual(try allowances().map(\.amount), [15])
    }

    func testTurningItOnOnPaydayLogsToday() throws {
        plan(turnedOn: payday); run(payday)
        XCTAssertEqual(try allowances().count, 1)
    }

    func testLogsNothingBeforePayday() throws {
        plan(turnedOn: day(-4)); run(day(-1))
        XCTAssertEqual(try allowances().count, 0)
    }

    func testDoesNotLogWeeksBeforeItWasTurnedOn() throws {
        plan(turnedOn: day(1)); run(day(2))
        XCTAssertEqual(try allowances().count, 0)
    }

    func testRunningTwiceLogsOnce() throws {
        plan(turnedOn: day(-2)); run(payday); run(payday); run(day(1))
        XCTAssertEqual(try allowances().count, 1)
    }

    func testCatchesUpOnMissedWeeks() throws {
        plan(turnedOn: day(-2)); run(day(15))
        XCTAssertEqual(try allowances().map { calendar.component(.day, from: $0.date) }, [6, 13, 20])
    }

    func testDeletedAllowanceDoesNotComeBack() throws {
        plan(turnedOn: day(-2)); run(payday)
        container.mainContext.delete(try allowances()[0])
        run(day(1))
        XCTAssertEqual(try allowances().count, 0)
    }

    func testSkipsAWeekLoggedByHand() throws {
        plan(turnedOn: day(-5))
        container.mainContext.insert(MoneyEntry(amount: 15, date: day(-2), kind: .allowance))
        run(payday)
        XCTAssertEqual(try allowances().count, 1)
    }

    func testLastWeeksAllowanceDoesNotBlockThisWeek() throws {
        plan(turnedOn: day(-5))
        container.mainContext.insert(MoneyEntry(amount: 15, date: day(-7), kind: .allowance))
        run(payday)
        XCTAssertEqual(try allowances().count, 2)
    }

    func testOffLogsNothing() throws {
        plan(turnedOn: day(-2)).setAllowance(weekday: nil, now: day(-1)); run(payday)
        XCTAssertEqual(try allowances().count, 0)
    }

    func testTurningItBackOnSkipsTheWeeksItWasOff() throws {
        let plan = plan(turnedOn: day(-2))
        plan.setAllowance(weekday: nil, now: day(-1))
        plan.setAllowance(weekday: Self.friday, now: day(10))
        run(day(12))
        XCTAssertEqual(try allowances().count, 0)
    }

    func testZeroAllowanceLogsNothing() throws {
        plan(turnedOn: day(-2)).allowancePerWeek = 0; run(payday)
        XCTAssertEqual(try allowances().count, 0)
    }

    func testNeverDatedInTheFuture() throws {
        plan(turnedOn: day(-2)); run(payday)
        XCTAssertLessThanOrEqual(try allowances()[0].date, payday)
    }

    func testAllowanceGoesIntoSpending() throws {
        plan(turnedOn: day(-2)); run(payday)
        XCTAssertEqual(Ledger(entries: try allowances()).balance(of: .spending), 15, accuracy: 0.01)
    }
}
