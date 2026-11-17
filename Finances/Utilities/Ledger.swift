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

/// Read-only view over logged entries: bucket balances, this week's spending, and pay by week.
/// Everything is worked out once in `init` (one pass over the entries), so reading it in a view body is cheap.
struct Ledger {
    let entries: [MoneyEntry]
    let calendar: Calendar
    /// Paychecks, oldest first.
    let paychecks: [MoneyEntry]
    let earned: Double
    let movedFromPaychecks: Double
    /// This week's purchases from Spending, newest first.
    let purchasesThisWeek: [MoneyEntry]
    let spentThisWeek: Double
    /// Days left in this week, today included.
    let daysLeftThisWeek: Int
    private let balances: [Bucket: Double]
    private let transfersByPaycheck: [UUID: [Bucket: MoneyEntry]]

    init(entries: [MoneyEntry], now: Date = .now, calendar: Calendar = .current) {
        self.entries = entries
        self.calendar = calendar
        let week = calendar.dateInterval(of: .weekOfYear, for: now)

        var paychecks: [MoneyEntry] = []
        var purchases: [MoneyEntry] = []
        var balances: [Bucket: Double] = [:]
        var transfers: [UUID: [Bucket: MoneyEntry]] = [:]
        var moved = 0.0
        for entry in entries {
            let kind = entry.kind
            let bucket = entry.bucket
            if let bucket { balances[bucket, default: 0] += entry.bucketEffect }
            switch kind {
            case .paycheck:
                paychecks.append(entry)
            case .transfer:
                moved += entry.amount
                if let paycheckID = entry.linkedPaycheckID, let bucket { transfers[paycheckID, default: [:]][bucket] = entry }
            case .spending:
                if let week, week.contains(entry.date) { purchases.append(entry) }
            case .gas, .allowance:
                break
            }
        }

        self.paychecks = paychecks.sorted { $0.date < $1.date }
        self.earned = paychecks.reduce(0) { $0 + $1.amount }
        self.movedFromPaychecks = moved
        self.purchasesThisWeek = purchases.sorted { $0.date > $1.date }
        self.spentThisWeek = purchases.reduce(0) { $0 + $1.amount }
        self.balances = balances
        self.transfersByPaycheck = transfers
        if let week {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: week.end).day ?? 1
            self.daysLeftThisWeek = max(1, days)
        } else {
            self.daysLeftThisWeek = 1
        }
    }

    var latestPaycheck: MoneyEntry? { paychecks.last }

    /// Paycheck money that hasn't been moved into a bucket yet.
    var notYetMoved: Double { max(0, earned - movedFromPaychecks) }

    func balance(of bucket: Bucket) -> Double { balances[bucket] ?? 0 }

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

    func transfer(from paycheck: MoneyEntry, to bucket: Bucket) -> MoneyEntry? {
        transfersByPaycheck[paycheck.entryID]?[bucket]
    }

    /// Transfers that came from a paycheck, so they can be removed with it.
    func transfers(from paycheck: MoneyEntry) -> [MoneyEntry] {
        Array((transfersByPaycheck[paycheck.entryID] ?? [:]).values)
    }
}
