import SwiftUI
import SwiftData

struct TrackingView: View {
    @Environment(\.modelContext) private var modelContext
    let categories: [BudgetCategory]
    let entries: [MoneyEntry]

    @State private var showingAdd = false
    @State private var kind: EntryKind = .paycheck
    @State private var amount: Double = 0
    @State private var date: Date = .now
    @State private var note: String = ""
    @State private var selectedCategory: BudgetCategory?

    private var incomeTotal: Double {
        entries.filter(\.isIncome).reduce(0) { $0 + $1.amount }
    }

    private var spendingTotal: Double {
        entries.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Live tracking")
                        .font(.largeTitle.weight(.semibold))
                    Text("Log paychecks and spending through the summer, then compare actuals to your plan and allocations.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    metric("Paychecks", MoneyFormat.string(incomeTotal), .green)
                    metric("Spending", MoneyFormat.string(spendingTotal), .orange)
                    metric("Net", MoneyFormat.string(incomeTotal - spendingTotal), .primary)
                    Spacer(minLength: 0)
                    Button {
                        resetDraft()
                        showingAdd = true
                    } label: {
                        Label("Add entry", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if entries.isEmpty {
                    EmptyHint(text: "Nothing logged yet. Add a paycheck when you get paid, or spending when you buy gas, invest, or save.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            HStack {
                                EntryRow(entry: entry)
                                if let category = entry.category, !entry.isIncome {
                                    Text(category.name)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(category.color.opacity(0.18), in: Capsule())
                                }
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            if entry.persistentModelID != entries.last?.persistentModelID {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(28)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("Tracking")
        .sheet(isPresented: $showingAdd) {
            addSheet
        }
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(EntryKind.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Amount", value: $amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Note", text: $note)

                if kind == .spending {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Uncategorized").tag(Optional<BudgetCategory>.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                }
            }
            .padding()
            .frame(width: 420, height: 300)
            .navigationTitle("New entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEntry() }
                        .disabled(amount <= 0)
                }
            }
            .onChange(of: kind) { _, newValue in
                if newValue == .paycheck {
                    selectedCategory = nil
                }
            }
        }
    }

    private func resetDraft() {
        kind = .paycheck
        amount = 0
        date = .now
        note = ""
        selectedCategory = nil
    }

    private func saveEntry() {
        let entry = MoneyEntry(
            amount: amount.clampedNonNegative,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            category: kind == .spending ? selectedCategory : nil
        )
        modelContext.insert(entry)
        try? modelContext.save()
        showingAdd = false
    }

    private func delete(_ entry: MoneyEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }
}
