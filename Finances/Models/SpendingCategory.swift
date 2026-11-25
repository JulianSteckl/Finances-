import Foundation

/// What a purchase was for.
enum SpendingCategory: String, CaseIterable, Identifiable, Codable {
    case food
    case fun
    case clothes
    case games
    case gifts
    case other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .food: "Food"
        case .fun: "Fun"
        case .clothes: "Clothes"
        case .games: "Games"
        case .gifts: "Gifts"
        case .other: "Other"
        }
    }

    /// Shown for purchases that don't have one yet.
    static let missingName = "No category"

    /// The category used the last time something with the same name was bought.
    static func suggested(for note: String, from entries: [MoneyEntry]) -> SpendingCategory? {
        let wanted = normalized(note)
        guard !wanted.isEmpty else { return nil }
        return entries
            .filter { $0.kind == .spending && $0.spendingCategory != nil && normalized($0.note) == wanted }
            .max { $0.date < $1.date }?
            .spendingCategory
    }

    private static func normalized(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
