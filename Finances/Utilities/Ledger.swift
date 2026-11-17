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
struct Ledger {
    let entries: [MoneyEntry]
    var calendar: Calendar = .current

    var paychecks: [MoneyEntry] {
        entries.filter { $0.kind == .paycheck }.sorted { $0.date < $1.date }
    }

    var latestPaycheck: MoneyEntry? { paychecks.last }

    var earned: Double { paychecks.reduce(0) { $0 + $1.amount } }

    var movedFromPaychecks: Double {
        entries.filter { $0.kind == .transfer }.reduce(0) { $0 + $1.amount }
    }

    /// Paycheck money that hasn't been moved into a bucket yet.
    var notYetMoved: Double { max(0, earned - movedFromPaychecks) }

    func balance(of bucket: Bucket) -> Double {
        entries.filter { $0.bucket == bucket }.reduce(0) { $0 + $1.bucketEffect }
    }

    func purchasesThisWeek(now: Date = .now) -> [MoneyEntry] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return entries
            .filter { $0.kind == .spending && week.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    func spentThisWeek(now: Date = .now) -> Double {
        purchasesThisWeek(now: now).reduce(0) { $0 + $1.amount }
    }

    /// Days left in this week, today included.
    func daysLeftThisWeek(now: Date = .now) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 1 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: week.end).day ?? 1
        return max(1, days)
    }

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
        entries.first { $0.kind == .transfer && $0.linkedPaycheckID == paycheck.entryID && $0.bucket == bucket }
    }
}
