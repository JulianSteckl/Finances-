import Foundation
import OSLog
import SwiftData

extension ModelContext {
    /// Saves pending changes, logging instead of silently dropping a failure.
    func saveChanges() {
        do {
            try save()
        } catch {
            Logger(subsystem: "Finances", category: "Storage").error("Save failed: \(error.localizedDescription)")
            assertionFailure("Save failed: \(error)")
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
    private let latestTransfers: [Bucket: MoneyEntry]
    private let transfersByPaycheck: [UUID: [MoneyEntry]]

    init(entries: [MoneyEntry], calendar: Calendar = .current) {
        self.entries = entries
        self.calendar = calendar

        var paychecks: [MoneyEntry] = []
        var purchases: [(date: Date, amount: Double)] = []
        var balances: [Bucket: Double] = [:]
        var movedTo: [Bucket: Double] = [:]
        var latestTransfers: [Bucket: MoneyEntry] = [:]
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
                if latestTransfers[bucket].map({ entry.createdAt > $0.createdAt }) ?? true {
                    latestTransfers[bucket] = entry
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
        self.latestTransfers = latestTransfers
        self.transfersByPaycheck = transfersByPaycheck
    }

    var latestPaycheck: MoneyEntry? { paychecks.last }

    func balance(of bucket: Bucket) -> Double { balances[bucket] ?? 0 }

    /// The most recent move into a bucket, so a checklist tick can be undone.
    func latestTransfer(to bucket: Bucket) -> MoneyEntry? { latestTransfers[bucket] }

    /// Pay earned in each week counted from `start` (index 0 = first week), up to the latest paycheck.
    func weeklyPay(from start: Date) -> [Double] {
        let startDay = calendar.startOfDay(for: start)
        var weeks: [Double] = []
        for paycheck in paychecks {
            let days = calendar.dateComponents([.day], from: startDay, to: paycheck.date).day ?? 0
            let index = max(0, days / 7)
            if weeks.count <= index { weeks.append(contentsOf: Array(repeating: 0, count: index - weeks.count + 1)) }
            weeks[index] += paycheck.amount
        }
        return weeks
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
    let start: Date
    let paidByWeek: [Double]
    let currentWeek: Int
    let forecast: PayForecast
    /// Projected summer pay compared with the plan: 1 means on plan, 0.9 means 10% less.
    let incomeScale: Double
    let spendingWeek: SpendingWeek
    let projection: [Bucket: [Double]]
    /// How much still needs moving into each bucket.
    let stillToMove: [Bucket: Double]

    init(plan: IncomePlan?, ledger: Ledger, now: Date = .now) {
        let inputs = plan?.inputs ?? .base
        let yearPlan = YearPlan(inputs)
        let start = plan?.weekNumberingStart(firstPaycheck: ledger.paychecks.first?.date) ?? now
        let paidByWeek = ledger.weeklyPay(from: start)
        let forecast = PayForecast(paid: paidByWeek, expectedPerWeek: yearPlan.weeklyPay, totalWeeks: inputs.weeksOfWork)
        let incomeScale = ledger.paychecks.isEmpty || yearPlan.jobTotal <= 0 ? 1 : forecast.projectedTotal / yearPlan.jobTotal

        self.inputs = inputs
        self.yearPlan = yearPlan
        self.ledger = ledger
        self.start = start
        self.paidByWeek = paidByWeek
        self.currentWeek = WeekCounter.week(of: now, from: start)
        self.forecast = forecast
        self.incomeScale = incomeScale
        self.spendingWeek = SpendingWeek(
            purchases: ledger.purchases, start: start, now: now,
            baseWeekly: yearPlan.weeklySpending(incomeScale: incomeScale), calendar: ledger.calendar
        )
        self.projection = yearPlan.projection(paid: paidByWeek)
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

    var waitingToMove: Double {
        stillToMove.values.reduce(0) { $0 + max(0, $1) }
    }
}

enum WeekCounter {
    static let weeksPerYear = 52

    /// 1-based week number of `date`, counted from `start`, kept within 1...52.
    static func week(of date: Date, from start: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: date).day ?? 0
        return min(weeksPerYear, max(1, days / 7 + 1))
    }
}
