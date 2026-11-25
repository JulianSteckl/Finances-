import XCTest

final class YearPlanTests: XCTestCase {
    private let base = YearPlan(.base)

    private func plan(_ change: (inout PlanInputs) -> Void) -> YearPlan {
        var inputs = PlanInputs.base
        change(&inputs)
        return YearPlan(inputs)
    }

    func testBaseJobTotal() { XCTAssertEqual(base.jobTotal, 7670, accuracy: 0.01) }
    func testBaseTotalIn() { XCTAssertEqual(base.totalIn, 8450, accuracy: 0.01) }
    func testBaseStocks() { XCTAssertEqual(base.stocksTotal, 3210, accuracy: 0.01) }
    func testBaseGas() { XCTAssertEqual(base.gasTotal, 1300, accuracy: 0.01) }

    func testSharesAddUpToOne() {
        XCTAssertEqual(base.paycheckShares.values.reduce(0, +), 1, accuracy: 1e-9)
    }

    func testSplitOfOnePaycheck() {
        let split = base.split(paycheck: 590)
        XCTAssertEqual(split[.gas]!, 100, accuracy: 0.01)
        XCTAssertEqual(split[.spending]!, 120, accuracy: 0.01)
        XCTAssertEqual(split[.savings]!, 123.08, accuracy: 0.01)
        XCTAssertEqual(split[.stocks]!, 246.92, accuracy: 0.01)
    }

    func testProjectionHasStartPlusOnePointPerWeek() {
        XCTAssertEqual(base.projection()[.stocks]!.count, 53)
    }

    func testSpendingRunsOutAtWeek52() {
        XCTAssertEqual(base.projection()[.spending]!.last!, 0, accuracy: 0.5)
    }

    func testGasRunsOutAtWeek52() {
        XCTAssertEqual(base.projection()[.gas]!.last!, 0, accuracy: 0.5)
    }

    func testYearEndIncludesGrowth() {
        XCTAssertGreaterThan(base.savedAndInvestedAtYearEnd(), 4810)
    }

    func testOverBudgetWhenPayIsTooLow() {
        let poor = plan { $0.hourlyWage = 5 }
        XCTAssertTrue(poor.isOverBudget)
        XCTAssertEqual(poor.paycheckShares[.stocks], 0)
        XCTAssertEqual(poor.paycheckShares.values.reduce(0, +), 1, accuracy: 1e-9)
    }

    func testNoPayGivesZeroShares() {
        XCTAssertTrue(plan { $0.hourlyWage = 0 }.paycheckShares.values.allSatisfy { $0 == 0 })
    }

    func testTaxLowersJobTotal() {
        XCTAssertEqual(plan { $0.taxRate = 0.1 }.jobTotal, 6903, accuracy: 0.01)
    }

    func testStartingMoneyGoesToStocks() {
        XCTAssertEqual(plan { $0.startingMoney = 500 }.stocksTotal, 3710, accuracy: 0.01)
    }

    func testRepeatingBeatsInvestingOnce() {
        let growth = base.stocksOverYears()
        XCTAssertEqual(growth.repeating.count, 6)
        XCTAssertGreaterThan(growth.repeating.last!, growth.once.last!)
    }

    func testWeeklySpendingOnPlan() {
        XCTAssertEqual(base.weeklySpending(incomeScale: 1), 45, accuracy: 0.01)
    }

    func testLessPayTrimsOnlyTheJobPart() {
        XCTAssertEqual(base.weeklySpending(incomeScale: 0.9), 42, accuracy: 0.01)
    }

    func testNoPayLeavesTheAllowance() {
        XCTAssertEqual(base.weeklySpending(incomeScale: 0), 15, accuracy: 0.01)
    }
}

final class MoveMoneyTests: XCTestCase {
    private let base = YearPlan(.base)

    func testTwoPaychecksOwed() {
        let owed = base.stillToMove(earned: 1180, movedTo: [:])
        XCTAssertEqual(owed[.gas]!, 200, accuracy: 0.01)
        XCTAssertEqual(owed[.stocks]!, 493.84, accuracy: 0.01)
    }

    func testMovedMoneyIsSubtracted() {
        let owed = base.stillToMove(earned: 1180, movedTo: [.gas: 200, .stocks: 246.92])
        XCTAssertEqual(owed[.gas]!, 0, accuracy: 0.01)
        XCTAssertEqual(owed[.stocks]!, 246.92, accuracy: 0.01)
    }

    func testHalfMoveIsSplitByNeed() {
        let half = MoveSplit.split(885, stillToMove: [.stocks: 740.76, .savings: 369.24, .spending: 360, .gas: 300])
        XCTAssertEqual(half[.stocks]!, 370.38, accuracy: 0.01)
        XCTAssertEqual(half.values.reduce(0, +), 885, accuracy: 0.01)
    }

    func testNeverMovesMoreThanNeeded() {
        let split = MoveSplit.split(5000, stillToMove: [.stocks: 100, .gas: 300])
        XCTAssertEqual(split.values.reduce(0, +), 400, accuracy: 0.01)
    }

    func testFullBucketsGetNothing() {
        let split = MoveSplit.split(100, stillToMove: [.stocks: 100, .savings: 0, .spending: -20, .gas: 0])
        XCTAssertEqual(split[.stocks]!, 100, accuracy: 0.01)
        XCTAssertEqual(split[.spending]!, 0, accuracy: 0.01)
    }

    func testNothingToMove() {
        XCTAssertTrue(MoveSplit.split(50, stillToMove: [:]).values.allSatisfy { $0 == 0 })
    }
}

final class PlanStatusTests: XCTestCase {
    func testWithinFivePercentIsOnTrack() { XCTAssertEqual(PlanStatus.of(actual: 1430, planned: 1480), .onTrack) }
    func testUnderIsBehind() { XCTAssertEqual(PlanStatus.of(actual: 310, planned: 450), .behind) }
    func testOverIsAhead() { XCTAssertEqual(PlanStatus.of(actual: 612, planned: 540), .ahead) }
    func testNothingPlannedNothingSaved() { XCTAssertEqual(PlanStatus.of(actual: 0, planned: 0), .onTrack) }
    func testMoneyWithNothingPlanned() { XCTAssertEqual(PlanStatus.of(actual: 50, planned: 0), .ahead) }
}

final class SpendingWeekTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: start)! }

    private func week(_ purchases: [(date: Date, amount: Double)], now: Int) -> SpendingWeek {
        SpendingWeek(purchases: purchases, start: start, now: day(now), baseWeekly: 45, calendar: calendar)
    }

    func testFirstWeekHasNoRollover() { XCTAssertEqual(week([], now: 2).available, 45, accuracy: 0.01) }
    func testUnspentRollsOver() { XCTAssertEqual(week([(day(1), 20)], now: 8).available, 70, accuracy: 0.01) }
    func testOverspendingComesOffNextWeek() { XCTAssertEqual(week([(day(1), 60)], now: 8).available, 30, accuracy: 0.01) }

    func testOnlyThisWeeksPurchasesCount() {
        let result = week([(day(1), 10), (day(9), 12.5)], now: 10)
        XCTAssertEqual(result.spentThisWeek, 12.5, accuracy: 0.01)
        XCTAssertEqual(result.left, 67.5, accuracy: 0.01)
    }

    func testDaysLeftCountsToday() { XCTAssertEqual(week([], now: 10).daysLeft, 4) }

    private func week(spent: Double = 0, bucket: Double) -> SpendingWeek {
        SpendingWeek(purchases: [(day(1), spent)], start: start, now: day(2), baseWeekly: 45, bucketBalance: bucket, calendar: calendar)
    }

    func testLeftStopsAtTheBucketBalance() { XCTAssertEqual(week(bucket: 30).left, 30, accuracy: 0.01) }
    func testEmptyBucketLeavesNothing() { XCTAssertEqual(week(bucket: 0).left, 0, accuracy: 0.01) }
    func testOverdrawnBucketShowsTheShortfall() { XCTAssertEqual(week(spent: 10, bucket: -10).left, -10, accuracy: 0.01) }
    func testFullBucketKeepsThePlanAmount() { XCTAssertEqual(week(bucket: 500).left, 45, accuracy: 0.01) }
    func testFullBucketIsNotLimited() { XCTAssertFalse(week(bucket: 500).isLimitedByBucket) }
    func testLowBucketIsLimited() { XCTAssertTrue(week(bucket: 30).isLimitedByBucket) }
    func testCappedWeekCountsWhatWasAlreadySpent() { XCTAssertEqual(week(spent: 10, bucket: 20).available, 30, accuracy: 0.01) }
}

final class PayForecastTests: XCTestCase {
    func testEstimateBlendsThreePlanWeeks() {
        let forecast = PayForecast(paid: [590, 590, 550, 610, 590, 590], expectedPerWeek: 590, totalWeeks: 13)
        XCTAssertEqual(forecast.weeklyEstimate, 5290.0 / 9, accuracy: 0.01)
        XCTAssertEqual(forecast.projectedTotal, 3520 + 7 * 5290.0 / 9, accuracy: 0.01)
    }

    func testNoPaychecksForecastsThePlan() {
        XCTAssertEqual(PayForecast(paid: [], expectedPerWeek: 590, totalWeeks: 13).projectedTotal, 7670, accuracy: 0.01)
    }

    func testOddWeekIsLimitedInThePace() {
        XCTAssertEqual(PayForecast(paid: [8250], expectedPerWeek: 750, totalWeeks: 12).paceScale, 1.125, accuracy: 0.001)
    }

    func testPaycheckWithoutHoursUsesItsAmount() {
        let weeks = PayWeeks.spread([.init(week: 0, amount: 1500, hours: 0)], hoursPerWeek: 30, expectedPerWeek: 750)
        XCTAssertEqual(weeks, [750, 750])
    }
}
