import Foundation

/// The four places every dollar goes: the money plan's buckets in Greenlight.
enum Bucket: String, CaseIterable, Identifiable, Codable {
    case stocks
    case savings
    case spending
    case gas

    var id: String { rawValue }

    var name: String {
        switch self {
        case .stocks: "Stocks"
        case .savings: "Savings"
        case .spending: "Spending"
        case .gas: "Gas"
        }
    }

    var systemImage: String {
        switch self {
        case .stocks: "chart.line.uptrend.xyaxis"
        case .savings: "building.columns"
        case .spending: "cart"
        case .gas: "fuelpump"
        }
    }

    /// One line on how the plan sizes this bucket.
    var rule: String {
        switch self {
        case .stocks: "Whatever is left after the other three"
        case .savings: "School-year savings goal"
        case .spending: "Weekly spending money, minus allowance"
        case .gas: "Gas every two weeks, all year"
        }
    }
}
