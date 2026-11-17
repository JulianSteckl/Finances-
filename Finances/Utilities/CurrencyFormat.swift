import Foundation
import SwiftUI

enum MoneyFormat {
    static let currency: FloatingPointFormatStyle<Double>.Currency = .currency(code: Locale.current.currency?.identifier ?? "USD")

    static func string(_ value: Double) -> String {
        value.formatted(currency)
    }

    /// Rounded to the dollar, for big summary numbers.
    static func whole(_ value: Double) -> String {
        value.formatted(currency.precision(.fractionLength(0)))
    }

    /// "+$590.00" or "−$12.50".
    static func signed(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + string(abs(value))
    }

    /// "$1.5k" style, for chart axes.
    static func compact(_ value: Double) -> String {
        value >= 1000 ? "$" + (value / 1000).formatted(.number.precision(.fractionLength(0...1))) + "k" : whole(value)
    }
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension Double {
    var clampedNonNegative: Double { max(0, self) }
}
