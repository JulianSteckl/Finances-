import Foundation
import SwiftData
import SwiftUI

enum AllocationMode: String, Codable, CaseIterable, Identifiable {
    case percent
    case dollars

    var id: String { rawValue }

    var label: String {
        switch self {
        case .percent: "Percent"
        case .dollars: "Dollars"
        }
    }
}

/// Legacy v1 custom bucket. No longer shown (the plan now uses the four fixed `Bucket`s),
/// but kept in the schema so data saved by v1 still opens.
@Model
final class BudgetCategory {
    var name: String
    var modeRaw: String
    var allocationValue: Double
    var sortOrder: Int
    var symbolName: String
    var colorHex: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \MoneyEntry.category)
    var entries: [MoneyEntry] = []

    init(
        name: String,
        mode: AllocationMode = .percent,
        allocationValue: Double,
        sortOrder: Int = 0,
        symbolName: String = "circle.fill",
        colorHex: String = "#4A90A4",
        createdAt: Date = .now
    ) {
        self.name = name
        self.modeRaw = mode.rawValue
        self.allocationValue = allocationValue
        self.sortOrder = sortOrder
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    var mode: AllocationMode {
        get { AllocationMode(rawValue: modeRaw) ?? .percent }
        set { modeRaw = newValue.rawValue }
    }

    func plannedAmount(forIncome income: Double) -> Double {
        switch mode {
        case .percent:
            return income * (allocationValue / 100)
        case .dollars:
            return allocationValue
        }
    }

    var color: Color {
        Color(hex: colorHex) ?? .accentColor
    }
}
