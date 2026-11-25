import Foundation
import SwiftData

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case paycheck
    /// A purchase paid from the Spending bucket. Raw value kept as "spending" so v1 entries still load.
    case spending
    case gas
    case allowance
    /// Money moved from a paycheck into a bucket.
    case transfer

    var id: String { rawValue }

    /// Kinds offered in the "New entry" form. Transfers come from the checklist instead.
    static let loggable: [EntryKind] = [.paycheck, .spending, .gas, .allowance]

    var label: String {
        switch self {
        case .paycheck: "Paycheck"
        case .spending: "Spending"
        case .gas: "Gas"
        case .allowance: "Allowance"
        case .transfer: "Moved"
        }
    }

    var systemImage: String {
        switch self {
        case .paycheck: "banknote"
        case .spending: "cart"
        case .gas: "fuelpump"
        case .allowance: "gift"
        case .transfer: "arrow.right.circle"
        }
    }

    /// Money coming in from outside, rather than moved or spent.
    var isIncome: Bool { self == .paycheck || self == .allowance }
}

@Model
final class MoneyEntry {
    var amount: Double
    var date: Date
    var note: String
    var kindRaw: String
    var createdAt: Date
    /// Legacy v1 category link. Kept so older data still opens; new entries use `bucketRaw`.
    var category: BudgetCategory?

    var entryID: UUID = UUID()
    var bucketRaw: String?
    /// Hours worked, for paychecks.
    var hours: Double = 0
    /// For transfers: the paycheck this money was moved from.
    var linkedPaycheckID: UUID?
    /// For purchases: what it was for.
    var spendingCategoryRaw: String?

    init(
        amount: Double,
        date: Date = .now,
        note: String = "",
        kind: EntryKind,
        bucket: Bucket? = nil,
        hours: Double = 0,
        linkedPaycheckID: UUID? = nil,
        spendingCategory: SpendingCategory? = nil,
        createdAt: Date = .now
    ) {
        self.amount = amount
        self.date = date
        self.note = note
        self.kindRaw = kind.rawValue
        self.bucketRaw = bucket?.rawValue
        self.hours = hours
        self.linkedPaycheckID = linkedPaycheckID
        self.spendingCategoryRaw = kind == .spending ? spendingCategory?.rawValue : nil
        self.createdAt = createdAt
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .spending }
        set { kindRaw = newValue.rawValue }
    }

    /// The bucket this entry adds to or takes from, if any.
    var bucket: Bucket? {
        switch kind {
        case .paycheck: nil
        case .spending, .allowance: .spending
        case .gas: .gas
        case .transfer: bucketRaw.flatMap(Bucket.init(rawValue:))
        }
    }

    var spendingCategory: SpendingCategory? {
        get { spendingCategoryRaw.flatMap(SpendingCategory.init(rawValue:)) }
        set { spendingCategoryRaw = newValue?.rawValue }
    }

    var isIncome: Bool { kind.isIncome }

    /// Signed effect on the bucket it belongs to.
    var bucketEffect: Double {
        switch kind {
        case .paycheck: 0
        case .allowance, .transfer: amount
        case .spending, .gas: -amount
        }
    }

    var title: String {
        if !note.isEmpty { return note }
        switch kind {
        case .paycheck: return hours > 0 ? "Paycheck · \(hours.formatted()) hrs" : "Paycheck"
        case .transfer: return "Moved to \(bucket?.name ?? "bucket")"
        default: return kind.label
        }
    }
}
