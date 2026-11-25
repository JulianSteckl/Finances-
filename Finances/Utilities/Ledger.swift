import Foundation
import OSLog
import SwiftData

extension ModelContext {
    /// Saves pending changes, logging instead of silently dropping a failure. Returns whether it worked.
    @discardableResult
    func saveChanges() -> Bool {
        do {
            try save()
            return true
        } catch {
            Logger(subsystem: "Finances", category: "Storage").error("Save failed: \(error.localizedDescription)")
            assertionFailure("Save failed: \(error)")
            return false
        }
    }
}

/// Read-only view over logged entries: bucket balances, money moved, purchases and pay by week.
/// Everything is worked out once in `init` (one pass over the entries), so reading it in a view body is cheap.
struct Ledger {
    let entries: [MoneyEntry]
    let calendar: Calendar
    /// Paychecks, oldest first.
    let paychecks: [MoneyEntry]
    let earned: Double
    /// Money moved into each bucket.
    let movedTo: [Bucket: Double]
    /// Purchases from Spending, any date.
    let purchases: [(date: Date, amount: Double)]
    private let balances: [Bucket: Double]
    /// The transfers from the most recent "Move", so it can be undone in one go.
    let lastMove: [MoneyEntry]
    private let transfersByPaycheck: [UUID: [MoneyEntry]]

    init(entries: [MoneyEntry], calendar: Calendar = .current) {
        self.entries = entries
        self.calendar = calendar

        var paychecks: [MoneyEntry] = []
        var purchases: [(date: Date, amount: Double)] = []
        var balances: [Bucket: Double] = [:]
        var movedTo: [Bucket: Double] = [:]
        var lastMove: [MoneyEntry] = []
        var transfersByPaycheck: [UUID: [MoneyEntry]] = [:]
        for entry in entries {
            let bucket = entry.bucket
            if let bucket { balances[bucket, default: 0] += entry.bucketEffect }
            switch entry.kind {
            case .paycheck:
                paychecks.append(entry)
            case .transfer:
                guard let bucket else { break }
                movedTo[bucket, default: 0] += entry.amount
                // A "Move" saves all its transfers with the same timestamp, so they group together.
                if let newest = lastMove.first?.createdAt {
                    if entry.createdAt > newest { lastMove = [entry] } else if entry.createdAt == newest { lastMove.append(entry) }
                } else {
                    lastMove = [entry]
                }
                if let paycheckID = entry.linkedPaycheckID { transfersByPaycheck[paycheckID, default: []].append(entry) }
            case .spending:
                purchases.append((entry.date, entry.amount))
            case .gas, .allowance:
                break
            }
        }

        self.paychecks = paychecks.sorted { $0.date < $1.date }
        self.earned = paychecks.reduce(0) { $0 + $1.amount }
        self.movedTo = movedTo
        self.purchases = purchases
        self.balances = balances
        self.lastMove = lastMove
        self.transfersByPaycheck = transfersByPaycheck
    }

    var latestPaycheck: MoneyEntry? { paychecks.last }

    func balance(of bucket: Bucket) -> Double { balances[bucket] ?? 0 }

    /// Summer job pay per week of work, and pay from odd jobs outside it. Without a job date, all pay is odd jobs.
    func pay(jobStart: Date?, inputs: PlanInputs, expectedPerWeek: Double) -> (byWeek: [Double], other: Double) {
        guard let jobStart else { return ([], earned) }
        let startDay = calendar.startOfDay(for: jobStart)
        var fromJob: [PayWeeks.Paycheck] = []
        var other = 0.0
        for paycheck in paychecks {
            let days = calendar.dateComponents([.day], from: startDay, to: calendar.startOfDay(for: paycheck.date)).day ?? 0
            let week = days < 0 ? -1 : days / 7
            if PayWeeks.isFromJob(week: week, weeksOfWork: inputs.weeksOfWork) {
                fromJob.append(.init(week: week, amount: paycheck.amount, hours: paycheck.hours))
            } else {
                other += paycheck.amount
            }
        }
        return (PayWeeks.spread(fromJob, hoursPerWeek: inputs.hoursPerWeek, expectedPerWeek: expectedPerWeek), other)
    }

    /// Older checklist moves that were tied to one paycheck, so they can be removed with it.
    func transfers(from paycheck: MoneyEntry) -> [MoneyEntry] {
        transfersByPaycheck[paycheck.entryID] ?? []
    }
}

/// Everything the screens show, worked out once from the plan and the log.
struct MoneyContext {
    let inputs: PlanInputs
    let yearPlan: YearPlan
    let ledger: Ledger
    /// First day of the summer job, if it's known.
    let jobStart: Date?
    /// Summer job pay for each week of work.
    let paidByWeek: [Double]
    /// Pay from odd jobs before or after the summer job.
    let otherPay: Double
    /// Week of the summer job's year, or 0 before it starts.
    let currentWeek: Int
    let forecast: PayForecast
    /// Typical weekly pay compared with the plan: 1 means on plan, 0.9 means 10% less.
    let incomeScale: Double
    let spendingWeek: SpendingWeek
    let projection: [Bucket: [Double]]
    /// How much still needs moving into each bucket.
    let stillToMove: [Bucket: Double]

    init(plan: IncomePlan?, ledger: Ledger, now: Date = .now) {
        let inputs = plan?.inputs ?? .base
        let yearPlan = YearPlan(inputs)
        let jobStart = plan?.jobStartDate
        let (paidByWeek, otherPay) = ledger.pay(jobStart: jobStart, inputs: inputs, expectedPerWeek: yearPlan.weeklyPay)
        // Spending weeks run all year, from the first money in or the job's start, whichever is earlier.
        let spendingStart = min(now, [ledger.paychecks.first?.date, jobStart].compactMap { $0 }.min() ?? now)
        let forecast = PayForecast(paid: paidByWeek, expectedPerWeek: yearPlan.weeklyPay, totalWeeks: inputs.weeksOfWork)
        let incomeScale = forecast.paceScale

        self.inputs = inputs
        self.yearPlan = yearPlan
        self.ledger = ledger
        self.jobStart = jobStart
        self.paidByWeek = paidByWeek
        self.otherPay = otherPay
        // Paychecks logged ahead of the calendar count as weeks already worked.
        let calendarWeek = jobStart.map { WeekCounter.week(of: now, from: $0, calendar: ledger.calendar) } ?? 0
        self.currentWeek = min(WeekCounter.weeksPerYear, max(calendarWeek, paidByWeek.count))
        self.forecast = forecast
        self.incomeScale = incomeScale
        self.spendingWeek = SpendingWeek(
            purchases: ledger.purchases, start: spendingStart, now: now,
            baseWeekly: yearPlan.weeklySpending(incomeScale: incomeScale),
            bucketBalance: ledger.balance(of: .spending), calendar: ledger.calendar
        )
        self.projection = yearPlan.projection(paid: paidByWeek, otherPay: otherPay)
        self.stillToMove = yearPlan.stillToMove(earned: ledger.earned, movedTo: ledger.movedTo)
    }

    /// Where the plan says a bucket's balance should be by now.
    func plannedBalance(of bucket: Bucket) -> Double {
        let series = projection[bucket] ?? []
        guard !series.isEmpty else { return 0 }
        return series[min(series.count - 1, max(0, currentWeek))]
    }

    var savedAndInvestedAtYearEnd: Double {
        (projection[.stocks]?.last ?? 0) + (projection[.savings]?.last ?? 0)
    }

    /// Pay from the summer job alone.
    var jobPay: Double { forecast.earned }

    var waitingToMove: Double {
        stillToMove.values.reduce(0) { $0 + max(0, $1) }
    }
}
