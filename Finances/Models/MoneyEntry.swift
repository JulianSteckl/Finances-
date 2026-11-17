import Foundation
import SwiftData

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case paycheck
    case spending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paycheck: "Paycheck"
        case .spending: "Spending"
        }
    }

    var systemImage: String {
        switch self {
        case .paycheck: "arrow.down.circle.fill"
        case .spending: "arrow.up.circle.fill"
        }
    }
}

@Model
final class MoneyEntry {
    var amount: Double
    var date: Date
    var note: String
    var kindRaw: String
    var createdAt: Date
    var category: BudgetCategory?

    init(
        amount: Double,
        date: Date = .now,
        note: String = "",
        kind: EntryKind,
        category: BudgetCategory? = nil,
        createdAt: Date = .now
    ) {
        self.amount = amount
        self.date = date
        self.note = note
        self.kindRaw = kind.rawValue
        self.category = category
        self.createdAt = createdAt
    }

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .spending }
        set { kindRaw = newValue.rawValue }
    }

    var isIncome: Bool { kind == .paycheck }
}
