import SwiftUI
import SwiftData

struct AllocationsView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?
    let categories: [BudgetCategory]

    @State private var showingAdd = false
    @State private var draftName = ""
    @State private var draftMode: AllocationMode = .percent
    @State private var draftValue: Double = 10
    @State private var draftSymbol = "tag.fill"
    @State private var draftColor = "#6B7280"

    private var plannedIncome: Double { plan?.plannedIncome ?? 0 }
    private var allocated: Double {
        FinanceMath.allocatedTotal(categories: categories, income: plannedIncome)
    }
    private var remaining: Double {
        FinanceMath.remainingToAllocate(categories: categories, income: plannedIncome)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allocation planner")
                        .font(.largeTitle.weight(.semibold))
                    Text("Split planned income across stocks, savings, gas, or any custom bucket — by percent or dollars.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    metric("Planned income", MoneyFormat.string(plannedIncome))
                    metric("Allocated", MoneyFormat.string(allocated))
                    metric(
                        remaining >= -0.5 ? "Remaining" : "Over",
                        MoneyFormat.string(abs(remaining))
                    )
                }

                HStack {
                    Text("Categories")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        resetDraft()
                        showingAdd = true
                    } label: {
                        Label("Add category", systemImage: "plus")
                    }
                }

                if categories.isEmpty {
                    EmptyHint(text: "No categories yet. Add Stocks, Savings, Gas, or your own buckets.")
                } else {
                    VStack(spacing: 12) {
                        ForEach(categories) { category in
                            CategoryEditorRow(
                                category: category,
                                plannedIncome: plannedIncome,
                                onDelete: { delete(category) }
                            )
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("Allocations")
        .sheet(isPresented: $showingAdd) {
            addSheet
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draftName)
                Picker("Mode", selection: $draftMode) {
                    ForEach(AllocationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if draftMode == .percent {
                    TextField("Percent", value: $draftValue, format: .number)
                } else {
                    TextField("Dollars", value: $draftValue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                }
                TextField("SF Symbol name", text: $draftSymbol)
                TextField("Color hex", text: $draftColor)
            }
            .padding()
            .frame(width: 420, height: 280)
            .navigationTitle("New category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addCategory() }
                        .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func resetDraft() {
        draftName = ""
        draftMode = .percent
        draftValue = 10
        draftSymbol = "tag.fill"
        draftColor = "#6B7280"
    }

    private func addCategory() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        let category = BudgetCategory(
            name: name,
            mode: draftMode,
            allocationValue: draftValue.clampedNonNegative,
            sortOrder: nextOrder,
            symbolName: draftSymbol.isEmpty ? "tag.fill" : draftSymbol,
            colorHex: draftColor.hasPrefix("#") ? draftColor : "#\(draftColor)"
        )
        modelContext.insert(category)
        try? modelContext.save()
        showingAdd = false
    }

    private func delete(_ category: BudgetCategory) {
        modelContext.delete(category)
        try? modelContext.save()
    }
}

struct CategoryEditorRow: View {
    @Bindable var category: BudgetCategory
    let plannedIncome: Double
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.color)
                    .frame(width: 22)
                TextField("Name", text: $category.name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                Spacer()
                Text(MoneyFormat.string(category.plannedAmount(forIncome: plannedIncome)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete category")
            }

            HStack(spacing: 12) {
                Picker("Mode", selection: modeBinding) {
                    ForEach(AllocationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                if category.mode == .percent {
                    TextField("Percent", value: $category.allocationValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("% of planned income")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Dollars", value: $category.allocationValue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Text("fixed amount")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private var modeBinding: Binding<AllocationMode> {
        Binding(
            get: { category.mode },
            set: { category.mode = $0 }
        )
    }
}
