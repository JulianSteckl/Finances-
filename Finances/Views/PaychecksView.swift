import SwiftUI
import SwiftData

struct PaychecksView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?
    let ledger: Ledger

    @State private var pendingDelete: MoneyEntry?

    var body: some View {
        let context = MoneyContext(plan: plan, ledger: ledger)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow: "Log a paycheck, purchase, gas fill-up or allowance", title: "Paychecks & log")
                    .appearEffect(order: 0)
                // The form keeps its own state, so typing only redraws the form and its split preview.
                NewEntrySection(
                    inputs: context.inputs, yearPlan: context.yearPlan,
                    spendingLeft: context.spendingWeek.left, gasBalance: ledger.balance(of: .gas)
                )
                .appearEffect(order: 1)
                LogCard(entries: ledger.entries) { pendingDelete = $0 }
                    .appearEffect(order: 2)
                SummerPayCard(context: context)
                    .appearEffect(order: 3)
            }
            .padding(Theme.pagePadding)
        }
        .background(Theme.background)
        .navigationTitle("Paychecks & log")
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { entry in
            Button("Delete \(entry.title)", role: .destructive) { delete(entry) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func delete(_ entry: MoneyEntry) {
        if entry.kind == .paycheck {
            // Older checklist moves tied to this paycheck go with it.
            ledger.transfers(from: entry).forEach(modelContext.delete)
        }
        modelContext.delete(entry)
        modelContext.saveChanges()
        pendingDelete = nil
    }
}

// MARK: - New entry

/// The "New entry" form and its live split preview.
struct NewEntrySection: View {
    @Environment(\.modelContext) private var modelContext
    let inputs: PlanInputs
    let yearPlan: YearPlan
    let spendingLeft: Double
    let gasBalance: Double

    @State private var kind: EntryKind = .paycheck
    @State private var amount: Double = 0
    @State private var hours: Double = 0
    @State private var date: Date = .now
    @State private var note = ""

    var body: some View {
        ResponsiveRow(leadingWeight: 0.9) {
            entryForm
        } trailing: {
            SplitPreviewCard(yearPlan: yearPlan, amount: kind == .paycheck && amount > 0 ? amount : yearPlan.weeklyPay)
        }
        .onAppear(perform: resetDraft)
    }

    private var entryForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "New entry")
            Picker("Type", selection: $kind) {
                ForEach(EntryKind.loggable) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: kind) { _, _ in resetAmount() }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    field("Amount") {
                        TextField("Amount", value: $amount, format: MoneyFormat.currency)
                    }
                    if kind == .paycheck {
                        field("Hours worked") { TextField("Hours", value: $hours, format: .number) }
                    } else {
                        field("What was it?") { TextField("e.g. Lunch", text: $note) }
                    }
                }
                GridRow {
                    field("Date") {
                        DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                    }
                }
            }
            Text(hint).font(.caption).foregroundStyle(Theme.muted).animatedNumber(hint)
            Button("Save entry", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amount <= 0)
                .keyboardShortcut(.defaultAction)
        }
        .textFieldStyle(.roundedBorder)
        .card()
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private var hint: String {
        switch kind {
        case .paycheck:
            let perHour = hours > 0 ? MoneyFormat.string(amount / hours) : "—"
            return "Works out to \(perHour) an hour (plan: \(MoneyFormat.string(inputs.hourlyWage)))"
        case .spending:
            return "Left this week after this: \(MoneyFormat.string(spendingLeft - amount))"
        case .gas:
            return "Gas bucket after this: \(MoneyFormat.string(gasBalance - amount))"
        case .allowance, .transfer:
            return "Goes straight into Spending"
        }
    }

    private func save() {
        guard amount > 0 else { return }
        let entry = MoneyEntry(
            amount: amount,
            date: date,
            note: kind == .paycheck ? "" : note.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            hours: kind == .paycheck ? max(0, hours) : 0
        )
        modelContext.insert(entry)
        modelContext.saveChanges()
        resetDraft()
    }

    private func resetDraft() {
        note = ""
        date = .now
        hours = inputs.hoursPerWeek
        resetAmount()
    }

    private func resetAmount() {
        switch kind {
        case .paycheck: amount = (yearPlan.weeklyPay * 100).rounded() / 100
        case .allowance: amount = inputs.allowancePerWeek
        default: amount = 0
        }
    }
}

struct SplitPreviewCard: View {
    let yearPlan: YearPlan
    let amount: Double

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let shares = yearPlan.paycheckShares
        let split = yearPlan.split(paycheck: amount)
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "How this paycheck splits", trailing: MoneyFormat.string(amount))
            BucketSplitBar(shares: shares, height: 14)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Bucket.allCases) { bucket in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            BucketDot(bucket: bucket)
                            Text("\(bucket.name) · \(((shares[bucket] ?? 0) * 100).formatted(.number.precision(.fractionLength(1))))%")
                                .animatedNumber(shares[bucket] ?? 0)
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text(MoneyFormat.string(split[bucket] ?? 0)).font(.system(size: 20, weight: .bold)).monospacedDigit()
                            .animatedNumber(split[bucket] ?? 0)
                        Text(bucket.rule).font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                }
            }
            Text("Shares come from your plan. The Overview's \"Move your money\" list adds up every paycheck for you.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }
}

// MARK: - Log

/// The full log, filtered, searchable and folded by month so it stays short as it grows.
struct LogCard: View {
    let entries: [MoneyEntry]
    let onDelete: (MoneyEntry) -> Void

    @State private var filter: LogFilter = .all
    @State private var search = ""
    @State private var expanded: Set<String> = []
    @State private var didOpenNewest = false

    enum LogFilter: String, CaseIterable, Identifiable {
        case all, paychecks, spending, gas, allowance, moves
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "All"
            case .paychecks: "Paychecks"
            case .spending: "Spending"
            case .gas: "Gas"
            case .allowance: "Allowance"
            case .moves: "Moves"
            }
        }

        func matches(_ kind: EntryKind) -> Bool {
            switch self {
            case .all: true
            case .paychecks: kind == .paycheck
            case .spending: kind == .spending
            case .gas: kind == .gas
            case .allowance: kind == .allowance
            case .moves: kind == .transfer
            }
        }
    }

    struct MonthGroup: Identifiable {
        let id: String
        let title: String
        var entries: [MoneyEntry]
        var moneyIn: Double
        var moneyOut: Double
    }

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private var filtered: [MoneyEntry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            guard filter.matches(entry.kind) else { return false }
            guard !query.isEmpty else { return true }
            let haystack = [entry.title, entry.kind.label, entry.bucket?.name ?? "", MoneyFormat.string(entry.amount),
                            entry.date.formatted(date: .abbreviated, time: .omitted)].joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    /// Entries are already newest first, so months come out newest first too.
    private func groups(of items: [MoneyEntry]) -> [MonthGroup] {
        let calendar = Calendar.current
        var result: [MonthGroup] = []
        for entry in items {
            let parts = calendar.dateComponents([.year, .month], from: entry.date)
            let key = "\(parts.year ?? 0)-\(parts.month ?? 0)"
            if result.last?.id != key {
                result.append(MonthGroup(id: key, title: entry.date.formatted(.dateTime.month(.wide).year()), entries: [], moneyIn: 0, moneyOut: 0))
            }
            result[result.count - 1].entries.append(entry)
            if entry.kind.isIncome { result[result.count - 1].moneyIn += entry.amount }
            if entry.kind == .spending || entry.kind == .gas { result[result.count - 1].moneyOut += entry.amount }
        }
        return result
    }

    var body: some View {
        let items = filtered
        let months = groups(of: items)
        return VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Log", trailing: items.count == entries.count ? "\(entries.count) entries" : "\(items.count) of \(entries.count) entries")
            controls(months: months)
            if months.isEmpty {
                EmptyHint(text: entries.isEmpty ? "Nothing logged yet." : "Nothing matches that filter.")
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(months) { month in
                    monthHeader(month)
                    if isSearching || expanded.contains(month.id) {
                        ForEach(month.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
        .card()
        .onAppear {
            guard !didOpenNewest, let newest = months.first else { return }
            expanded.insert(newest.id)
            didOpenNewest = true
        }
    }

    private func controls(months: [MonthGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search the log", text: $search).textFieldStyle(.plain)
                    if isSearching {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 280)
                Spacer()
                let allOpen = !months.isEmpty && months.allSatisfy { expanded.contains($0.id) }
                Button(allOpen ? "Collapse all" : "Expand all") {
                    withAnimation(Motion.quick) {
                        expanded = allOpen ? [] : Set(months.map(\.id))
                    }
                }
                .buttonStyle(.link)
                .disabled(months.isEmpty || isSearching)
            }
            Picker("Show", selection: $filter.animation(Motion.quick)) {
                ForEach(LogFilter.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func monthHeader(_ month: MonthGroup) -> some View {
        let open = isSearching || expanded.contains(month.id)
        return Button {
            withAnimation(Motion.quick) {
                if expanded.contains(month.id) { expanded.remove(month.id) } else { expanded.insert(month.id) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundStyle(Theme.muted)
                Text(month.title).fontWeight(.semibold)
                Text("\(month.entries.count)").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Text("In \(MoneyFormat.string(month.moneyIn))").font(.caption).foregroundStyle(Theme.muted).animatedNumber(month.moneyIn)
                Text("Out \(MoneyFormat.string(month.moneyOut))").font(.caption).foregroundStyle(Theme.muted).animatedNumber(month.moneyOut)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSearching)
        .accessibilityLabel("\(month.title), \(month.entries.count) entries")
        .accessibilityValue(open ? "Expanded" : "Collapsed")
    }

    private func entryRow(_ entry: MoneyEntry) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                EntryRow(entry: entry)
                Button {
                    onDelete(entry)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.muted)
                .help("Delete entry")
                .accessibilityLabel("Delete \(entry.title)")
            }
            .padding(.leading, 20)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Summer pay

/// How summer pay is going, as one bar and one plain sentence.
struct SummerPayCard: View {
    let context: MoneyContext
    @State private var reveal: Double = 0

    var body: some View {
        let forecast = context.forecast
        let plan = context.yearPlan.jobTotal
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Summer pay")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MoneyFormat.whole(forecast.earned)).font(.system(size: 26, weight: .bold)).monospacedDigit().animatedNumber(forecast.earned)
                Text("earned of your \(MoneyFormat.whole(plan)) plan").foregroundStyle(Theme.muted)
            }
            paceBar(earned: forecast.earned, projected: forecast.projectedTotal, plan: plan)
            HStack(spacing: 16) {
                key(Theme.ink, "Earned")
                key(Theme.muted.opacity(0.3), "Still to come at your pace")
                HStack(spacing: 5) {
                    Rectangle().fill(Theme.ink).frame(width: 2, height: 12)
                    Text("Plan")
                }
            }
            .font(.caption).foregroundStyle(Theme.muted)
            Text(explanation).fixedSize(horizontal: false, vertical: true).animatedNumber(forecast.projectedTotal)
        }
        .card()
        .revealOnAppear($reveal)
    }

    private var explanation: String {
        let forecast = context.forecast
        guard forecast.weeksWorked > 0 else {
            return "Log your first paycheck and this shows whether you're on pace for your plan."
        }
        let difference = forecast.projectedTotal - context.yearPlan.jobTotal
        let weeksLeft = Int(forecast.weeksLeft.rounded())
        let pace = "You're making about \(MoneyFormat.whole(forecast.weeklyEstimate)) a week. With \(weeksLeft) week\(weeksLeft == 1 ? "" : "s") left, that's about \(MoneyFormat.whole(forecast.projectedTotal)) for the summer"
        if abs(difference) < 1 { return pace + ", right on plan." }
        return pace + ", \(MoneyFormat.whole(abs(difference))) \(difference > 0 ? "more" : "less") than planned. Spending and Stocks adjust to match."
    }

    private func paceBar(earned: Double, projected: Double, plan: Double) -> some View {
        let scaleMax = max(1, max(plan, projected))
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.chip)
                RoundedRectangle(cornerRadius: 6).fill(Theme.muted.opacity(0.3))
                    .frame(width: width * min(1, projected / scaleMax) * reveal)
                RoundedRectangle(cornerRadius: 6).fill(Theme.ink)
                    .frame(width: width * min(1, earned / scaleMax) * reveal)
                Rectangle().fill(Theme.ink)
                    .frame(width: 2, height: 24)
                    .offset(x: max(0, min(width - 2, width * plan / scaleMax - 1)))
            }
        }
        .frame(height: 16)
        .animation(Motion.smooth, value: projected)
        .accessibilityElement()
        .accessibilityLabel("Earned \(MoneyFormat.whole(earned)), on pace for \(MoneyFormat.whole(projected)), plan \(MoneyFormat.whole(plan))")
    }

    private func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }
}
