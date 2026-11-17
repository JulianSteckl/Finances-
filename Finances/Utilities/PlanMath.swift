import Foundation

/// Every number the money plan needs, kept apart from SwiftData so it can be tested and used for what-ifs.
struct PlanInputs: Equatable {
    static let weeksPerYear: Double = 52

    var hourlyWage: Double = 20
    var hoursPerWeek: Double = 29.5
    var weeksOfWork: Double = 13
    /// Overtime pay and tips earned on top of regular hours, per week.
    var extraPerWeek: Double = 0
    var oneTimeBonuses: Double = 0
    /// When above zero, replaces the calculated job total.
    var jobTotalOverride: Double = 0
    /// Share of pay withheld for taxes, 0...1.
    var taxRate: Double = 0
    var allowancePerWeek: Double = 15
    var spendingPerWeek: Double = 45
    var gasPerTwoWeeks: Double = 50
    var savingsGoal: Double = 1600
    var startingMoney: Double = 0
    /// Yearly growth, 0...1.
    var stockReturn: Double = 0.07
    var savingsReturn: Double = 0.02

    static let base = PlanInputs()
}

/// The year plan worked out from its inputs.
struct YearPlan {
    let inputs: PlanInputs

    init(_ inputs: PlanInputs) {
        self.inputs = inputs
    }

    private var weeksPerYear: Double { PlanInputs.weeksPerYear }
    private var keptAfterTax: Double { 1 - min(max(inputs.taxRate, 0), 1) }

    var weeklyPay: Double {
        (inputs.hourlyWage * inputs.hoursPerWeek + inputs.extraPerWeek) * keptAfterTax
    }

    var jobTotal: Double {
        if inputs.jobTotalOverride > 0 {
            return inputs.jobTotalOverride * keptAfterTax
        }
        return weeklyPay * inputs.weeksOfWork + inputs.oneTimeBonuses * keptAfterTax
    }

    var allowanceTotal: Double { inputs.allowancePerWeek * weeksPerYear }
    var totalIn: Double { jobTotal + allowanceTotal + inputs.startingMoney }
    var gasTotal: Double { inputs.gasPerTwoWeeks / 2 * weeksPerYear }
    var spendingTotal: Double { inputs.spendingPerWeek * weeksPerYear }
    /// Spending the allowance doesn't cover, so it has to come out of paychecks.
    var spendingFromJob: Double { max(0, spendingTotal - allowanceTotal) }
    var stocksTotal: Double { totalIn - gasTotal - spendingTotal - inputs.savingsGoal }
    var isOverBudget: Bool { stocksTotal < 0 }

    func yearTotal(for bucket: Bucket) -> Double {
        switch bucket {
        case .stocks: max(0, stocksTotal)
        case .savings: inputs.savingsGoal
        case .spending: spendingTotal
        case .gas: gasTotal
        }
    }

    /// Share of each paycheck that goes into each bucket. Shares add up to 1 whenever there is pay.
    var paycheckShares: [Bucket: Double] {
        guard jobTotal > 0 else {
            return Dictionary(uniqueKeysWithValues: Bucket.allCases.map { ($0, 0) })
        }
        let fixed: [Bucket: Double] = [.savings: inputs.savingsGoal, .spending: spendingFromJob, .gas: gasTotal]
        let fixedSum = fixed.values.reduce(0, +)
        if fixedSum >= jobTotal {
            // Not enough pay for the plan: fill the fixed buckets in proportion and leave stocks empty.
            var shares = fixed.mapValues { $0 / fixedSum }
            shares[.stocks] = 0
            return shares
        }
        var shares = fixed.mapValues { $0 / jobTotal }
        shares[.stocks] = (jobTotal - fixedSum) / jobTotal
        return shares
    }

    func split(paycheck amount: Double) -> [Bucket: Double] {
        paycheckShares.mapValues { $0 * amount }
    }

    /// Pay expected in a given week (1-based) of the year, counting a partial last week.
    func expectedPay(inWeek week: Int) -> Double {
        let workedPart = min(1, max(0, inputs.weeksOfWork - Double(week - 1)))
        return weeklyPay * workedPart
    }

    /// Balance of each bucket at the end of every week, index 0 being the start.
    /// `paid` replaces the expected pay for the first weeks with what was really earned.
    func projection(paid: [Double] = []) -> [Bucket: [Double]] {
        let shares = paycheckShares
        var balance: [Bucket: Double] = [.stocks: inputs.startingMoney, .savings: 0, .spending: 0, .gas: 0]
        var series = Dictionary(uniqueKeysWithValues: Bucket.allCases.map { ($0, [balance[$0] ?? 0]) })

        for week in 1...Int(weeksPerYear) {
            let pay = week <= paid.count ? paid[week - 1] : expectedPay(inWeek: week)
            for bucket in Bucket.allCases {
                balance[bucket, default: 0] += pay * (shares[bucket] ?? 0)
            }
            balance[.spending, default: 0] += inputs.allowancePerWeek - inputs.spendingPerWeek
            balance[.gas, default: 0] -= inputs.gasPerTwoWeeks / 2
            balance[.savings, default: 0] *= 1 + inputs.savingsReturn / weeksPerYear
            balance[.stocks, default: 0] *= 1 + inputs.stockReturn / weeksPerYear
            for bucket in Bucket.allCases {
                series[bucket, default: []].append(max(0, balance[bucket] ?? 0))
            }
        }
        return series
    }

    /// Stocks plus savings at the end of week 52, growth included.
    func savedAndInvestedAtYearEnd(paid: [Double] = []) -> Double {
        let series = projection(paid: paid)
        return (series[.stocks]?.last ?? 0) + (series[.savings]?.last ?? 0)
    }

    /// Stocks at the end of each year: putting in this year's amount every summer, or only this year.
    func stocksOverYears(_ years: Int = 5) -> (repeating: [Double], once: [Double]) {
        let firstYear = projection()[.stocks]?.last ?? 0
        var repeating: [Double] = [0]
        var once: [Double] = [0]
        for year in 1...max(1, years) {
            repeating.append(repeating[year - 1] * (1 + inputs.stockReturn) + firstYear)
            once.append(year == 1 ? firstYear : once[year - 1] * (1 + inputs.stockReturn))
        }
        return (repeating, once)
    }
}

extension YearPlan {
    /// Weekly spending money, scaled to how pay is really going.
    /// The part covered by allowance stays fixed; the part paid from your job grows or shrinks with `incomeScale`.
    func weeklySpending(incomeScale: Double) -> Double {
        let fromAllowance = min(inputs.spendingPerWeek, inputs.allowancePerWeek)
        let fromPay = max(0, inputs.spendingPerWeek - inputs.allowancePerWeek)
        return fromAllowance + fromPay * max(0, incomeScale)
    }

    /// How much still needs moving into each bucket, given the pay earned so far and what's already moved.
    /// Starting money counts toward Stocks. A negative value means more was moved than the plan asks for.
    func stillToMove(earned: Double, movedTo: [Bucket: Double]) -> [Bucket: Double] {
        let shares = paycheckShares
        var result: [Bucket: Double] = [:]
        for bucket in Bucket.allCases {
            let owed = earned * (shares[bucket] ?? 0) + (bucket == .stocks ? inputs.startingMoney : 0)
            result[bucket] = owed - (movedTo[bucket] ?? 0)
        }
        return result
    }
}

/// This week's spending money, with whatever wasn't spent in earlier weeks rolled over.
struct SpendingWeek {
    let baseWeekly: Double
    /// Unspent money from earlier weeks (negative if earlier weeks went over).
    let rolledOver: Double
    let spentThisWeek: Double
    let weekStart: Date
    let weekEnd: Date
    /// Days left in this week, today included.
    let daysLeft: Int

    var available: Double { baseWeekly + rolledOver }
    var left: Double { available - spentThisWeek }

    /// Weeks run in 7-day blocks from `start`, so they line up with the paycheck weeks.
    init(purchases: [(date: Date, amount: Double)], start: Date, now: Date, baseWeekly: Double, calendar: Calendar = .current) {
        let startDay = calendar.startOfDay(for: start)
        let daysSinceStart = max(0, calendar.dateComponents([.day], from: startDay, to: now).day ?? 0)
        let weekIndex = daysSinceStart / 7
        let weekStart = calendar.date(byAdding: .day, value: weekIndex * 7, to: startDay) ?? startDay
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

        var spentBefore = 0.0
        var spentNow = 0.0
        for purchase in purchases where purchase.date >= startDay {
            if purchase.date < weekStart {
                spentBefore += purchase.amount
            } else if purchase.date < weekEnd {
                spentNow += purchase.amount
            }
        }

        self.baseWeekly = baseWeekly
        self.rolledOver = baseWeekly * Double(weekIndex) - spentBefore
        self.spentThisWeek = spentNow
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: weekEnd).day ?? 1
        self.daysLeft = max(1, days)
    }
}

/// Forecast of summer pay once real paychecks come in, blending them with the base estimate.
struct PayForecast {
    /// How many base-estimate weeks are mixed in, so one odd week doesn't swing the forecast.
    static let priorWeeks: Double = 3

    let paid: [Double]
    let expectedPerWeek: Double
    let totalWeeks: Double

    var earned: Double { paid.reduce(0, +) }
    var weeksWorked: Double { Double(paid.count) }
    var weeksLeft: Double { max(0, totalWeeks - weeksWorked) }

    var weeklyEstimate: Double {
        (earned + Self.priorWeeks * expectedPerWeek) / (weeksWorked + Self.priorWeeks)
    }

    var projectedTotal: Double { earned + weeksLeft * weeklyEstimate }
}
