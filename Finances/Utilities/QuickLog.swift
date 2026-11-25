import Foundation

/// Reading typed amounts and the short text shown in the menu bar.
enum QuickLog {
    /// Entry kinds offered in the menu bar box.
    static let kinds: [EntryKind] = [.spending, .gas, .allowance]

    private static let centsPerDollar: Double = 100

    /// "12", "12.5", "$12.50" or "1,234.56". Anything else, including zero, is nil rather than a guess:
    /// "12,50" must not be read as $1,250.
    static func amount(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.wholeMatch(of: /\$?\s?([0-9]{1,3}(,[0-9]{3})+|[0-9]*)(\.[0-9]{0,2})?/) != nil else { return nil }
        let digits = trimmed.filter { $0.isNumber || $0 == "." }
        guard let value = Double(digits), value > 0 else { return nil }
        return (value * centsPerDollar).rounded() / centsPerDollar
    }

    /// Whole dollars left, rounded down so it never shows more than there is.
    static func menuBarText(left: Double) -> String {
        // The small nudge keeps an exact $20 from showing as $19 after floating-point math.
        let dollars = (left + 0.001).rounded(.down)
        return MoneyFormat.whole(dollars == 0 ? 0 : dollars)
    }

    static func entry(kind: EntryKind, amount: Double, note: String, category: SpendingCategory? = nil, now: Date = .now) -> MoneyEntry {
        MoneyEntry(amount: amount, date: now, note: note.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, spendingCategory: category)
    }
}
