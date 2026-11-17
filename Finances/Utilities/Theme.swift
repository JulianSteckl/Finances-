import SwiftUI
import AppKit

/// Black-and-white palette. Every color adapts to light and dark mode.
enum Theme {
    static let ink = Color(light: 0x0A0A0A, dark: 0xF5F5F5)
    static let muted = Color(light: 0x595959, dark: 0xA3A3A3)
    static let background = Color(light: 0xF5F5F5, dark: 0x000000)
    static let panel = Color(light: 0xFFFFFF, dark: 0x0F0F0F)
    static let line = Color(light: 0xE0E0E0, dark: 0x262626)
    static let chip = Color(light: 0xEBEBEB, dark: 0x1F1F1F)
    /// Text and icons drawn on top of `ink` (buttons, ticked boxes).
    static let onInk = Color(light: 0xFFFFFF, dark: 0x0A0A0A)
    static let summerShade = Color(light: 0x000000, dark: 0xFFFFFF).opacity(0.04)

    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 18
    static let gap: CGFloat = 16
    static let pagePadding: CGFloat = 28
}

extension Color {
    /// A color with separate light- and dark-mode values, given as 0xRRGGBB.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Bucket {
    /// Shades of gray, darkest to lightest (flipped in dark mode), so buckets differ by lightness.
    var color: Color {
        switch self {
        case .stocks: Color(light: 0x0A0A0A, dark: 0xFAFAFA)
        case .savings: Color(light: 0x525252, dark: 0xB3B3B3)
        case .spending: Color(light: 0x8A8A8A, dark: 0x7A7A7A)
        case .gas: Color(light: 0xBDBDBD, dark: 0x4D4D4D)
        }
    }

    /// Line pattern for charts, so lines can be told apart without color.
    var dash: [CGFloat] {
        switch self {
        case .stocks, .savings: []
        case .spending: [2, 3]
        case .gas: [7, 4]
        }
    }
}

// MARK: - Motion

/// Shared animation timings, kept short so the app stays quick.
enum Motion {
    static let quick = Animation.snappy(duration: 0.22)
    static let smooth = Animation.smooth(duration: 0.4)
    static let reveal = Animation.easeOut(duration: 0.7)
    static let cardStagger: Double = 0.04
    static let maxStaggeredCards = 6
    static let appearOffset: CGFloat = 10
}

/// Fades and lifts a card in when its screen opens, a little after the one before it.
struct AppearEffect: ViewModifier {
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Motion.appearOffset)
            .onAppear {
                guard !shown else { return }
                let delay = Double(min(order, Motion.maxStaggeredCards)) * Motion.cardStagger
                withAnimation(reduceMotion ? nil : Motion.smooth.delay(delay)) { shown = true }
            }
    }
}

/// Goes from 0 to 1 once when a chart appears, so lines and bars can grow in.
struct RevealProgress: ViewModifier {
    @Binding var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onAppear {
            guard progress < 1 else { return }
            withAnimation(reduceMotion ? nil : Motion.reveal) { progress = 1 }
        }
    }
}

extension View {
    func appearEffect(order: Int) -> some View { modifier(AppearEffect(order: order)) }
    func revealOnAppear(_ progress: Binding<Double>) -> some View { modifier(RevealProgress(progress: progress)) }

    /// Rolls digits when a number changes.
    func animatedNumber<Value: Equatable>(_ value: Value) -> some View {
        contentTransition(.numericText()).animation(Motion.smooth, value: value)
    }
}

// MARK: - Shared building blocks

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct CardTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.4)
        }
    }
}

/// Big number with a label, an optional progress bar and a footnote.
struct KPITile: View {
    let label: String
    let value: String
    var progress: Double?
    var tint: Color = Theme.ink
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 26, weight: .bold)).monospacedDigit().tracking(-0.4)
                .animatedNumber(value)
            if let progress {
                ProgressBar(value: progress, tint: tint)
            }
            Text(footnote).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
        }
        .card()
    }
}

/// Kept for the plan settings screen.
struct SummaryCard: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        KPITile(label: title, value: value, footnote: footnote)
    }
}

struct ProgressBar: View {
    let value: Double
    var tint: Color = Theme.ink
    var height: CGFloat = 6
    @State private var reveal: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.chip)
                Capsule().fill(tint).frame(width: proxy.size.width * min(1, max(0, value)) * reveal)
            }
        }
        .revealOnAppear($reveal)
        .animation(Motion.smooth, value: value)
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(1, max(0, value))) * 100)) percent")
    }
}

/// One bar split into the four buckets by share.
struct BucketSplitBar: View {
    let shares: [Bucket: Double]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(Bucket.allCases.count - 1) * 2
            HStack(spacing: 2) {
                ForEach(Bucket.allCases) { bucket in
                    Rectangle()
                        .fill(bucket.color)
                        .frame(width: max(0, (proxy.size.width - gaps) * (shares[bucket] ?? 0)))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2))
        .animation(Motion.smooth, value: shares)
        .accessibilityHidden(true)
    }
}

struct BucketDot: View {
    let bucket: Bucket
    var body: some View {
        Circle().fill(bucket.color).frame(width: 8, height: 8)
    }
}

struct EmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

/// Lays two views side by side when there is room, otherwise stacks them.
/// A custom layout measures each child once per width, unlike `ViewThatFits`, which lays out every option.
struct ResponsiveRow<Leading: View, Trailing: View>: View {
    var minWideWidth: CGFloat = 760
    var leadingWeight: CGFloat = 1.6
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        SplitRowLayout(minWideWidth: minWideWidth, leadingWeight: leadingWeight, spacing: Theme.gap) {
            leading
            trailing
        }
    }
}

struct SplitRowLayout: Layout {
    let minWideWidth: CGFloat
    let leadingWeight: CGFloat
    let spacing: CGFloat

    private func columnWidths(for total: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let available = max(0, total - spacing)
        let leading = available * leadingWeight / (leadingWeight + 1)
        return (leading, available - leading)
    }

    private func height(of subview: LayoutSubview, width: CGFloat) -> CGFloat {
        subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? minWideWidth
        if width >= minWideWidth {
            let columns = columnWidths(for: width)
            return CGSize(width: width, height: max(height(of: subviews[0], width: columns.leading),
                                                    height(of: subviews[1], width: columns.trailing)))
        }
        return CGSize(width: width, height: height(of: subviews[0], width: width) + spacing + height(of: subviews[1], width: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if bounds.width >= minWideWidth {
            let columns = columnWidths(for: bounds.width)
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: columns.leading, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + columns.leading + spacing, y: bounds.minY),
                              proposal: ProposedViewSize(width: columns.trailing, height: nil))
        } else {
            let firstHeight = height(of: subviews[0], width: bounds.width)
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + firstHeight + spacing),
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(Theme.ink.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 9))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(Theme.panel.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 9))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
    }
}
