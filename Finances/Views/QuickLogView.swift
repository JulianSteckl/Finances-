import AppKit
import SwiftData
import SwiftUI

/// The menu bar item: what's left to spend this week, in whole dollars.
struct MenuBarLabel: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [IncomePlan]
    @Query private var entries: [MoneyEntry]
    /// Refreshed when the day changes, so a new week shows up without opening the app.
    @State private var now: Date = .now

    var body: some View {
        let context = MoneyContext(plan: plans.first, ledger: Ledger(entries: entries), now: now)
        let text = QuickLog.menuBarText(left: context.spendingWeek.left)
        return HStack(spacing: 4) {
            Image(systemName: "cart")
            Text(text)
        }
        .accessibilityLabel("Finances, \(text) left to spend this week")
        // Also covers launching without the main window.
        .onAppear { AutoAllowance.run(in: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            now = .now
            AutoAllowance.run(in: modelContext)
        }
    }
}

/// The box under the menu bar item: what's left, and one form to log a purchase, gas or allowance.
struct QuickLogView: View {
    static let mainWindowID = "main"

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [IncomePlan]
    @Query(sort: \MoneyEntry.date, order: .reverse, animation: Motion.smooth) private var entries: [MoneyEntry]

    @State private var kind: EntryKind = .spending
    @State private var amountText = ""
    @State private var note = ""
    @State private var lastSaved: Saved?
    @State private var saveFailed = false
    @FocusState private var focus: Field?

    private enum Field { case amount, note }

    /// A copy of what was logged, since the entry itself may be deleted in the main window.
    private struct Saved {
        let id: UUID
        let title: String
        let amount: Double
    }

    private static let width: CGFloat = 290
    private static let fieldHeight: CGFloat = 32

    private var amount: Double? { QuickLog.amount(from: amountText) }

    var body: some View {
        let context = MoneyContext(plan: plans.first, ledger: Ledger(entries: entries))
        return VStack(alignment: .leading, spacing: 14) {
            summary(context.spendingWeek)
            form(context)
            status
            Divider()
            footer
        }
        .padding(16)
        .frame(width: Self.width)
        .background(Theme.panel)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .onAppear { focus = .amount }
    }

    private func summary(_ week: SpendingWeek) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(MoneyFormat.string(week.left))
                    .font(.system(size: 26, weight: .bold)).monospacedDigit()
                    .animatedNumber(week.left)
                Text(week.isLimitedByBucket ? "left in bucket" : "left of \(MoneyFormat.string(week.available))")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            ProgressBar(value: week.available > 0 ? week.left / week.available : 0, tint: Bucket.spending.color)
        }
    }

    private func form(_ context: MoneyContext) -> some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $kind) {
                ForEach(QuickLog.kinds) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: kind) { _, newKind in
                amountText = newKind == .allowance ? MoneyFormat.string(context.inputs.allowancePerWeek) : ""
                focus = .amount
            }
            field("Amount", text: $amountText, field: .amount)
            if kind != .allowance {
                field(kind == .gas ? "Where?" : "What was it?", text: $note, field: .note)
            }
            Button(action: save) {
                Text(amount.map { "Log \(MoneyFormat.string($0))" } ?? "Log").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(amount == nil)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .focused($focus, equals: field)
            .onSubmit(save)
            .padding(.horizontal, 10)
            .frame(height: Self.fieldHeight)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(placeholder)
    }

    @ViewBuilder
    private var status: some View {
        if saveFailed {
            Text("Couldn't save. Try again.").font(.callout.weight(.semibold))
        } else if let lastSaved {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("\(lastSaved.title) · \(MoneyFormat.string(lastSaved.amount))").lineLimit(1)
                Spacer()
                Button("Undo", action: undo).buttonStyle(.link)
            }
            .font(.callout)
            .transition(.opacity)
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Finances", action: openMainWindow)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(Theme.muted)
    }

    private func save() {
        guard let amount else {
            focus = .amount
            return
        }
        let entry = QuickLog.entry(kind: kind, amount: amount, note: kind == .allowance ? "" : note)
        modelContext.insert(entry)
        guard modelContext.saveChanges() else {
            modelContext.delete(entry)
            saveFailed = true
            return
        }
        withAnimation(Motion.quick) {
            saveFailed = false
            lastSaved = Saved(id: entry.entryID, title: entry.title, amount: entry.amount)
        }
        amountText = ""
        note = ""
        focus = .amount
    }

    private func undo() {
        guard let savedID = lastSaved?.id else { return }
        withAnimation(Motion.quick) { lastSaved = nil }
        guard let entry = entries.first(where: { $0.entryID == savedID }) else { return }
        modelContext.delete(entry)
        modelContext.saveChanges()
    }

    /// Brings back the open window, or opens one if it was closed.
    private func openMainWindow() {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: Self.mainWindowID)
        }
    }
}
