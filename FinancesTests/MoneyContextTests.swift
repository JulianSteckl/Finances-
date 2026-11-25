import SwiftData
import XCTest

/// Whole-app numbers worked out from logged entries, using a throwaway in-memory store.
@MainActor
final class MoneyContextTests: XCTestCase {
    private var container: ModelContainer!
    private let calendar = Calendar.current
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 12))! }

    override func setUpWithError() throws {
        let schema = Schema([IncomePlan.self, BudgetCategory.self, MoneyEntry.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    /// $25/hr × 30 hrs × 12 weeks = $9,000, so a normal week is $750.
    private func plan() -> IncomePlan {
        let plan = IncomePlan(hoursPerWeek: 30, hourlyWage: 25, weeksInSeason: 12)
        plan.jobStart = start
        container.mainContext.insert(plan)
        return plan
    }

    private func paycheck(_ amount: Double, hours: Double, day: Int) -> MoneyEntry {
        let date = calendar.date(byAdding: .day, value: day, to: start)!
        let entry = MoneyEntry(amount: amount, date: date, kind: .paycheck, hours: hours)
        container.mainContext.insert(entry)
        return entry
    }

    private func context(_ entries: [MoneyEntry], day: Int = 0) -> MoneyContext {
        MoneyContext(plan: plan(), ledger: Ledger(entries: entries), now: calendar.date(byAdding: .day, value: day, to: start)!)
    }

    func testElevenNormalPaychecksLoggedOnOneDayKeepTheNormalWeeklySpending() {
        let result = context((0..<11).map { _ in paycheck(750, hours: 30, day: 0) })
        XCTAssertEqual(result.spendingWeek.baseWeekly, 45, accuracy: 0.01)
    }

    func testElevenNormalPaychecksLoggedOnOneDayStayOnPlan() {
        let result = context((0..<11).map { _ in paycheck(750, hours: 30, day: 0) })
        XCTAssertEqual(result.forecast.projectedTotal, 9000, accuracy: 0.01)
    }

    func testOneHugePaycheckBarelyRaisesWeeklySpending() {
        let result = context([paycheck(8250, hours: 30, day: 0)])
        XCTAssertLessThan(result.spendingWeek.baseWeekly, 50)
    }

    func testLowerPayLowersWeeklySpending() {
        let result = context((0..<6).map { paycheck(675, hours: 30, day: $0 * 7) }, day: 36)
        XCTAssertLessThan(result.spendingWeek.baseWeekly, 45)
    }

    func testSteadilyHigherPayRaisesWeeklySpending() {
        let result = context((0..<6).map { paycheck(825, hours: 33, day: $0 * 7) }, day: 36)
        XCTAssertGreaterThan(result.spendingWeek.baseWeekly, 45)
    }

    func testNoPaychecksUsesThePlan() {
        XCTAssertEqual(context([]).spendingWeek.baseWeekly, 45, accuracy: 0.01)
    }

    func testTwoHalfPaychecksInOneWeekCountAsOneWeek() {
        let result = context([paycheck(375, hours: 15, day: 0), paycheck(375, hours: 15, day: 3)])
        XCTAssertEqual(result.paidByWeek, [750])
    }

    func testOnePaycheckForTwoWeeksOfHoursCoversTwoWeeks() {
        XCTAssertEqual(context([paycheck(1500, hours: 60, day: 0)]).paidByWeek, [750, 750])
    }

    func testShortFirstWeekStillCountsAsOneWeek() {
        XCTAssertEqual(context([paycheck(100, hours: 5, day: 0)]).paidByWeek, [100])
    }

    func testWeekOffShowsAsZero() {
        let result = context([paycheck(750, hours: 30, day: 0), paycheck(750, hours: 30, day: 14)], day: 15)
        XCTAssertEqual(result.paidByWeek, [750, 0, 750])
    }

    func testEarnedTotalIsNeverChangedByGrouping() {
        let result = context((0..<11).map { _ in paycheck(750, hours: 30, day: 0) })
        XCTAssertEqual(result.paidByWeek.reduce(0, +), 8250, accuracy: 0.01)
    }

    private func entry(_ kind: EntryKind, _ amount: Double, day: Int, bucket: Bucket? = nil) -> MoneyEntry {
        let entry = MoneyEntry(amount: amount, date: calendar.date(byAdding: .day, value: day, to: start)!, kind: kind, bucket: bucket)
        container.mainContext.insert(entry)
        return entry
    }

    func testRolloverCannotExceedTheSpendingBucket() {
        let entries = [paycheck(750, hours: 30, day: 0), entry(.transfer, 81, day: 0, bucket: .spending)]
        XCTAssertEqual(context(entries, day: 8).spendingWeek.left, 81, accuracy: 0.01)
    }

    func testNothingMovedMeansNothingToSpend() {
        XCTAssertEqual(context([paycheck(750, hours: 30, day: 0)]).spendingWeek.left, 0, accuracy: 0.01)
    }

    func testPurchaseIsOnlySubtractedOnce() {
        let entries = [paycheck(750, hours: 30, day: 0), entry(.transfer, 30, day: 0, bucket: .spending), entry(.spending, 10, day: 1)]
        XCTAssertEqual(context(entries, day: 2).spendingWeek.left, 20, accuracy: 0.01)
    }

    // MARK: - Odd jobs before the summer job

    /// The base plan ($20/hr × 29.5 hrs × 13 weeks) with two odd jobs four weeks apart and no job date.
    private func oddJobs() -> MoneyContext {
        let plan = IncomePlan()
        container.mainContext.insert(plan)
        let entries = [paycheck(100, hours: 5, day: 0), paycheck(200, hours: 10, day: 28)]
        return MoneyContext(plan: plan, ledger: Ledger(entries: entries), now: calendar.date(byAdding: .day, value: 29, to: start)!)
    }

    func testOddJobsDoNotLowerWeeklySpending() { XCTAssertEqual(oddJobs().spendingWeek.baseWeekly, 45, accuracy: 0.01) }
    func testOddJobsDoNotLowerTheSummerForecast() { XCTAssertEqual(oddJobs().forecast.projectedTotal, 7670, accuracy: 0.01) }
    func testOddJobsAreStillWaitingToBeMoved() { XCTAssertEqual(oddJobs().waitingToMove, 300, accuracy: 0.01) }

    func testOddJobsAreNotWeeksOfWork() { XCTAssertEqual(oddJobs().paidByWeek, []) }
    func testOddJobsCountAsOtherPay() { XCTAssertEqual(oddJobs().otherPay, 300, accuracy: 0.01) }
    func testWithoutAJobDateTheJobHasNotStarted() { XCTAssertEqual(oddJobs().currentWeek, 0) }

    func testOddJobsRaiseTheYearEndProjection() {
        XCTAssertGreaterThan(oddJobs().savedAndInvestedAtYearEnd, YearPlan(.base).savedAndInvestedAtYearEnd())
    }

    func testOnlyPayFromTheJobStartCountsTowardTheJob() {
        let result = context([paycheck(100, hours: 5, day: -30), paycheck(750, hours: 30, day: 4)], day: 5)
        XCTAssertEqual(result.paidByWeek, [750])
        XCTAssertEqual(result.otherPay, 100, accuracy: 0.01)
    }

    func testFutureJobStartIsWeekZero() { XCTAssertEqual(context([], day: -10).currentWeek, 0) }
    func testJobStartDayIsWeekOne() { XCTAssertEqual(context([], day: 0).currentWeek, 1) }

    func testWaitingForTheFirstPaycheckDoesNotLowerThePace() {
        let result = context([paycheck(750, hours: 30, day: 11)], day: 11)
        XCTAssertEqual(result.spendingWeek.baseWeekly, 45, accuracy: 0.01)
    }

    func testBiweeklyPaycheckFillsTheWeeksItCovers() {
        let result = context([paycheck(1500, hours: 60, day: 11), paycheck(1500, hours: 60, day: 25)], day: 26)
        XCTAssertEqual(result.paidByWeek, [750, 750, 750, 750])
    }

    func testWeekOffDoesNotLowerWeeklySpending() {
        let result = context([paycheck(750, hours: 30, day: 0), paycheck(750, hours: 30, day: 14)], day: 15)
        XCTAssertEqual(result.spendingWeek.baseWeekly, 45, accuracy: 0.01)
    }

    func testOddJobInTheSchoolYearIsOtherPay() {
        let result = context([paycheck(750, hours: 30, day: 0), paycheck(100, hours: 5, day: 150)], day: 150)
        XCTAssertEqual(result.paidByWeek, [750])
        XCTAssertEqual(result.otherPay, 100, accuracy: 0.01)
    }

    func testLastPaycheckAfterTheJobEndsStillCounts() {
        XCTAssertEqual(context([paycheck(750, hours: 30, day: 12 * 7 + 4)], day: 90).otherPay, 0, accuracy: 0.01)
    }

    func testChangingWeeksInAWhatIfKeepsTheStartDate() {
        let plan = plan()
        plan.usesSeasonDates = true
        plan.seasonStart = start
        var draft = plan.inputs
        draft.weeksOfWork = 10
        plan.applyWhatIf(draft)
        XCTAssertEqual(plan.jobStartDate, start)
    }
}
