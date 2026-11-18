import SwiftUI
import AppKit
import SwiftData
import Charts

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: IncomePlan?
    let ledger: Ledger
    let onLogEntry: () -> Void

    private static let recentCount = 6

    var body: some View {
        let context = MoneyContext(plan: plan, ledger: ledger)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(context).appearEffect(order: 0)
                kpis(context).appearEffect(order: 1)
                // Short cards together, then the two bucket lists together, so rows line up.
                ResponsiveRow(leadingWeight: 1) {
                    WeeklyPayCard(context: context)
                } trailing: {
                    SpendingWeekCard(context: context)
                }
                .appearEffect(order: 2)
                ResponsiveRow(leadingWeight: 1) {
                    MoveMoneyCard(context: context, onMove: move, onUndo: undoLastMove)
                } trailing: {
                    BucketsVsPlanCard(context: context)
                }
                .appearEffect(order: 3)
                recentActivity.appearEffect(order: 4)
            }
            .padding(Theme.pagePadding)
        }
        .background(Theme.background)
        .navigationTitle("Overview")
    }

    private func header(_ context: MoneyContext) -> some View {
        HStack(alignment: .bottom) {
            PageHeader(eyebrow: weekLabel(context), title: "Overview")
            Spacer()
            Button(action: onLogEntry) {
                Label("Log entry", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("n")
        }
    }

    private func weekLabel(_ context: MoneyContext) -> String {
        let summerWeeks = Int(context.inputs.weeksOfWork.rounded(.up))
        let week = context.currentWeek
        return week <= summerWeeks
            ? "Week \(week) of \(summerWeeks) · summer job"
            : "Week \(week) of 52 · school year"
    }

    private func kpis(_ context: MoneyContext) -> some View {
        let yearPlan = context.yearPlan
        let savings = ledger.balance(of: .savings)
        let stocks = ledger.balance(of: .stocks)
        let savedGoal = yearPlan.yearTotal(for: .stocks) + yearPlan.yearTotal(for: .savings)
        let week = context.spendingWeek
        return TileGridLayout {
            KPITile(label: "Projected at week 52", value: MoneyFormat.whole(context.savedAndInvestedAtYearEnd), progress: 1)
            KPITile(label: "Earned this summer", value: MoneyFormat.whole(ledger.earned),
                    progress: yearPlan.jobTotal > 0 ? ledger.earned / yearPlan.jobTotal : 0,
                    footnote: "\(percent(ledger.earned, of: yearPlan.jobTotal)) of \(MoneyFormat.whole(yearPlan.jobTotal)) plan")
            KPITile(label: "Saved + invested", value: MoneyFormat.whole(savings + stocks),
                    progress: savedGoal > 0 ? (savings + stocks) / savedGoal : 0, tint: Bucket.savings.color,
                    footnote: "Savings \(MoneyFormat.whole(savings)) · Stocks \(MoneyFormat.whole(stocks))")
            KPITile(label: "Left to spend this week", value: MoneyFormat.string(week.left),
                    progress: week.available > 0 ? week.left / week.available : 0, tint: Bucket.spending.color,
                    footnote: "\(MoneyFormat.string(week.spentThisWeek)) spent of \(MoneyFormat.string(week.available))")
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CardTitle(title: "Recent activity")
                Button("See full log", action: onLogEntry).buttonStyle(.link)
            }
            if ledger.entries.isEmpty {
                EmptyHint(text: "Nothing logged yet. Log your first paycheck to get started.")
            } else {
                ForEach(Array(ledger.entries.prefix(Self.recentCount))) { entry in
                    Divider()
                    EntryRow(entry: entry)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .card()
    }

    private func move(_ amounts: [Bucket: Double]) {
        let movedAt = Date.now
        withAnimation(Motion.smooth) {
            for (bucket, amount) in amounts {
                let rounded = (amount * 100).rounded() / 100
                guard rounded > 0 else { continue }
                modelContext.insert(MoneyEntry(amount: rounded, kind: .transfer, bucket: bucket, createdAt: movedAt))
            }
            modelContext.saveChanges()
        }
    }

    private func undoLastMove() {
        guard !ledger.lastMove.isEmpty else { return }
        withAnimation(Motion.smooth) {
            ledger.lastMove.forEach(modelContext.delete)
            modelContext.saveChanges()
        }
    }

    private func percent(_ value: Double, of total: Double) -> String {
        total > 0 ? "\(Int((value / total * 100).rounded()))%" : "0%"
    }
}

// MARK: - Cards

/// One slider for how much is being moved now; the app splits it across the buckets.
struct MoveMoneyCard: View {
    let context: MoneyContext
    let onMove: ([Bucket: Double]) -> Void
    let onUndo: () -> Void

    /// Amount picked on the slider. `nil` means "everything that's waiting".
    @State private var picked: Double?
    /// True while the amount is being typed; otherwise it shows as a rolling number.
    @State private var isEditing = false
    @FocusState private var amountFocused: Bool
    /// Where the amount box is on screen, so a click anywhere else can end typing.
    @State private var fieldFrame: CGRect = .zero
    @State private var clickMonitor: Any?

    private static let tileColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    /// Below a cent there's nothing left to move.
    private static let minimumMove = 0.01

    var body: some View {
        let waiting = context.waitingToMove
        let moving = min(picked ?? waiting, waiting)
        let split = MoveSplit.split(moving, stillToMove: context.stillToMove)
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "Move your money", trailing: "\(MoneyFormat.string(waiting)) waiting")
            amountField(moving: moving, waiting: waiting)
            slider(moving: moving, waiting: waiting)
            BucketSplitBar(shares: shares(of: split, total: moving), height: 10)
            LazyVGrid(columns: Self.tileColumns, spacing: 10) {
                ForEach(Bucket.allCases) { bucket in
                    tile(bucket: bucket, amount: split[bucket] ?? 0)
                }
            }
            HStack(spacing: 10) {
                Button {
                    endEditing()
                    onMove(split)
                    picked = nil
                } label: {
                    Text(waiting < Self.minimumMove ? "All moved" : "Move \(MoneyFormat.string(moving))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(moving < Self.minimumMove)
                Button("Undo last move", action: onUndo)
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(context.ledger.lastMove.isEmpty)
            }
        }
        .card()
    }

    private func setAmount(_ value: Double, waiting: Double) {
        picked = min(waiting, max(0, (value * 100).rounded() / 100))
    }

    /// Shows the amount as a rolling number; click it to type an exact amount (cents allowed).
    /// Return, Escape, or a click anywhere outside the box ends typing.
    private func amountField(moving: Double, waiting: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ZStack(alignment: .leading) {
                TextField("Amount", value: Binding(get: { moving }, set: { setAmount($0, waiting: waiting) }), format: MoneyFormat.currency)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .fixedSize()
                    .focused($amountFocused)
                    .onSubmit(endEditing)
                    .onExitCommand(perform: endEditing)
                    .opacity(isEditing ? 1 : 0)
                    .allowsHitTesting(isEditing)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { fieldFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in fieldFrame = frame }
                    })
                Button(action: startEditing) {
                    Text(MoneyFormat.string(moving))
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                        .animatedNumber(moving)
                }
                .buttonStyle(.plain)
                .opacity(isEditing ? 0 : 1)
                .allowsHitTesting(!isEditing)
                .help("Click to type an exact amount")
                .accessibilityHint("Type an exact amount")
            }
            Text("moving now").foregroundStyle(Theme.muted)
        }
        .onDisappear(perform: stopWatchingClicks)
    }

    private func startEditing() {
        isEditing = true
        amountFocused = true
        watchForClicksOutside()
    }

    private func endEditing() {
        guard isEditing else { return }
        isEditing = false
        amountFocused = false
        // A Mac text box keeps the keyboard until something else takes it, so hand it back to the window.
        NSApp.keyWindow?.makeFirstResponder(nil)
        stopWatchingClicks()
    }

    /// A Mac doesn't move focus when you click empty space, so watch clicks while typing
    /// and end typing when one lands outside the amount box.
    private func watchForClicksOutside() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let contentView = event.window?.contentView {
                let point = event.locationInWindow
                let flipped = CGPoint(x: point.x, y: contentView.bounds.height - point.y)
                if !fieldFrame.contains(flipped) {
                    endEditing()
                }
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    /// Plain slider in whole dollars. Typing in the amount above still allows cents.
    private func slider(moving: Double, waiting: Double) -> some View {
        Slider(value: Binding(get: { moving }, set: { setAmount($0.rounded(), waiting: waiting) }),
               in: 0...max(Self.minimumMove, waiting)) {
            Text("Amount to move")
        }
        .labelsHidden()
        .tint(Theme.ink)
        .disabled(waiting < Self.minimumMove)
    }

    private func shares(of split: [Bucket: Double], total: Double) -> [Bucket: Double] {
        guard total > 0 else { return context.yearPlan.paycheckShares }
        return split.mapValues { $0 / total }
    }

    private func tile(bucket: Bucket, amount: Double) -> some View {
        let moved = context.ledger.movedTo[bucket] ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                BucketDot(bucket: bucket)
                Text(bucket.name)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Text(MoneyFormat.string(amount)).font(.system(size: 18, weight: .bold)).monospacedDigit().animatedNumber(amount)
            Text("\(MoneyFormat.string(moved)) moved").font(.caption).foregroundStyle(Theme.muted).animatedNumber(moved)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
    }
}

/// This week's spending money, with last weeks' leftovers rolled in and scaled to real pay.
struct SpendingWeekCard: View {
    let context: MoneyContext

    private static let ringSize: CGFloat = 132
    private static let ringWidth: CGFloat = 13
    private static let dayBarHeight: CGFloat = 64
    private static let daysPerWeek = 7
    private static let recentPurchaseCount = 3

    private struct Day: Identifiable {
        let date: Date
        let spent: Double
        let isToday: Bool
        var id: Date { date }
    }

    var body: some View {
        let week = context.spendingWeek
        let purchases = context.ledger.entries.filter { $0.kind == .spending && $0.date >= week.weekStart && $0.date < week.weekEnd }
        return VStack(alignment: .leading, spacing: 18) {
            CardTitle(title: "Spending this week", trailing: dateRange(week))
            HStack(alignment: .center, spacing: 22) {
                ring(week)
                stats(week)
            }
            dayStrip(week: week, purchases: purchases)
            recent(purchases)
        }
        .card()
    }

    private func dateRange(_ week: SpendingWeek) -> String {
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: week.weekEnd) ?? week.weekEnd
        return "\(week.weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(lastDay.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func stats(_ week: SpendingWeek) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
            GridRow {
                stat("Weekly amount", MoneyFormat.string(week.baseWeekly), week.baseWeekly)
                stat(week.rolledOver >= 0 ? "Rolled over" : "Over last weeks", MoneyFormat.signed(week.rolledOver), week.rolledOver)
            }
            GridRow {
                stat("Spent", MoneyFormat.string(week.spentThisWeek), week.spentThisWeek)
                stat("Per day · \(week.daysLeft) left", MoneyFormat.string(max(0, week.left) / Double(week.daysLeft)), week.left)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String, _ number: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 17, weight: .bold)).monospacedDigit().animatedNumber(number)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ring(_ week: SpendingWeek) -> some View {
        let fraction = week.available > 0 ? min(1, max(0, week.left / week.available)) : 0
        return ZStack {
            Circle().stroke(Theme.chip, lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Bucket.spending.color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.smooth, value: fraction)
            VStack(spacing: 0) {
                Text(MoneyFormat.string(week.left)).font(.system(size: 20, weight: .bold)).monospacedDigit().animatedNumber(week.left)
                Text("left of \(MoneyFormat.string(week.available))").font(.caption2).foregroundStyle(Theme.muted).animatedNumber(week.available)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityElement(children: .combine)
    }

    /// One bar per day of this week, with a line for an even daily share of the week's money.
    private func dayStrip(week: SpendingWeek, purchases: [MoneyEntry]) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days: [Day] = (0..<Self.daysPerWeek).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: week.weekStart) ?? week.weekStart
            let spent = purchases.filter { calendar.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.amount }
            return Day(date: date, spent: spent, isToday: calendar.isDate(date, inSameDayAs: today))
        }
        let dailyShare = week.available / Double(Self.daysPerWeek)
        let scaleMax = max(1, max(days.map(\.spent).max() ?? 0, dailyShare * 1.5))
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(days) { day in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.spent > 0 ? Bucket.spending.color : Theme.chip)
                            .frame(height: max(4, Self.dayBarHeight * day.spent / scaleMax))
                            .frame(maxWidth: .infinity)
                    }
                }
                Rectangle()
                    .fill(Theme.ink.opacity(0.5))
                    .frame(height: 1)
                    .padding(.bottom, Self.dayBarHeight * dailyShare / scaleMax)
            }
            .frame(height: Self.dayBarHeight, alignment: .bottom)
            .animation(Motion.smooth, value: days.map(\.spent))
            HStack(spacing: 8) {
                ForEach(days) { day in
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Spending by day this week")
    }

    private func recent(_ purchases: [MoneyEntry]) -> some View {
        VStack(spacing: 0) {
            if purchases.isEmpty {
                EmptyHint(text: "No purchases yet this week.")
            }
            ForEach(Array(purchases.prefix(Self.recentPurchaseCount))) { item in
                Divider()
                HStack {
                    Text(item.title)
                    Text("· \(item.date.formatted(.dateTime.weekday(.abbreviated)))").foregroundStyle(Theme.muted)
                    Spacer()
                    Text(MoneyFormat.signed(-item.amount)).fontWeight(.semibold).monospacedDigit()
                }
                .padding(.vertical, 7)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Four tiles, one per bucket: status, balance against the plan for now, and a bar with a plan mark.
struct BucketsVsPlanCard: View {
    let context: MoneyContext
    @State private var reveal: Double = 0

    /// Each tile's bar scales to its own bucket, with room past the plan mark for a bucket that's ahead.
    private static let barHeadroom = 1.1
    private static let tileSpacing: CGFloat = 10

    private struct Tile: Identifiable {
        let bucket: Bucket
        let actual: Double
        let planned: Double
        var status: PlanStatus { PlanStatus.of(actual: actual, planned: planned) }
        var id: Bucket { bucket }
    }

    var body: some View {
        let tiles = Bucket.allCases.map { Tile(bucket: $0, actual: context.ledger.balance(of: $0), planned: context.plannedBalance(of: $0)) }
        let onTrack = tiles.filter { $0.status == .onTrack }.count
        return VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Buckets vs plan", trailing: "\(onTrack) of \(tiles.count) on track · week \(context.currentWeek)")
            VStack(spacing: Self.tileSpacing) {
                HStack(spacing: Self.tileSpacing) {
                    tile(tiles[0])
                    tile(tiles[1])
                }
                HStack(spacing: Self.tileSpacing) {
                    tile(tiles[2])
                    tile(tiles[3])
                }
            }
            .frame(maxHeight: .infinity)
        }
        .card()
        .revealOnAppear($reveal)
    }

    private func tile(_ item: Tile) -> some View {
        let barMax = max(1, max(item.planned, item.actual) * Self.barHeadroom)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                BucketDot(bucket: item.bucket)
                Text(item.bucket.name).fontWeight(.semibold)
                Spacer(minLength: 4)
                StatusChip(status: item.status)
            }
            // Name at the top, amount in the middle, bar at the bottom, evenly spaced like the mockup.
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(MoneyFormat.whole(item.actual))
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .animatedNumber(item.actual)
                Text("of \(MoneyFormat.whole(item.planned))")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .animatedNumber(item.planned)
            }
            Spacer(minLength: 0)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chip)
                    Capsule().fill(item.bucket.color)
                        .frame(width: width * min(1, max(0, item.actual) / barMax) * reveal)
                    Rectangle().fill(Theme.ink)
                        .frame(width: 2, height: 12)
                        .offset(x: max(0, min(width - 2, width * item.planned / barMax - 1)))
                }
            }
            .frame(height: 6)
            .animation(Motion.smooth, value: item.actual)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
        .accessibilityElement(children: .combine)
    }
}

/// "On track" in gray, "Behind" filled black so it stands out, "Ahead" outlined.
struct StatusChip: View {
    let status: PlanStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .behind ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(status == .ahead ? Theme.ink : Color.clear))
            .animation(Motion.quick, value: status)
    }

    private var background: Color {
        switch status {
        case .behind: Theme.ink
        case .onTrack: Theme.chip
        case .ahead: Theme.panel
        }
    }
}

struct WeeklyPayCard: View {
    let context: MoneyContext
    @State private var reveal: Double = 0

    private struct Bar: Identifiable {
        let week: Int
        let amount: Double
        let isPaid: Bool
        var id: Int { week }
        var label: String { "\(week)" }
    }

    private var bars: [Bar] {
        let weeks = max(1, Int(context.inputs.weeksOfWork.rounded(.up)), context.paidByWeek.count)
        return (1...weeks).map { week in
            week <= context.paidByWeek.count
                ? Bar(week: week, amount: context.paidByWeek[week - 1], isPaid: true)
                : Bar(week: week, amount: context.yearPlan.expectedPay(inWeek: week), isPaid: false)
        }
    }

    /// Fixed top of the axis, so it doesn't rescale while bars grow in.
    private var yMax: Double {
        let highest = max(context.paidByWeek.max() ?? 0, context.yearPlan.weeklyPay)
        return max(100, (highest / 100).rounded(.up) * 100)
    }

    var body: some View {
        let forecast = context.forecast
        let average = context.paidByWeek.isEmpty ? 0 : forecast.earned / Double(context.paidByWeek.count)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                CardTitle(title: "Weekly pay")
                key(fill: Theme.ink, label: "Paid")
                key(fill: Theme.muted.opacity(0.3), label: "Expected")
            }
            chart.revealOnAppear($reveal)
            HStack(spacing: 20) {
                stat("Average", MoneyFormat.whole(average), average)
                stat("Plan", "\(MoneyFormat.whole(context.yearPlan.weeklyPay)) / wk", context.yearPlan.weeklyPay)
                stat("On pace for", MoneyFormat.whole(forecast.projectedTotal), forecast.projectedTotal)
            }
        }
        .card()
    }

    private var chart: some View {
        // Weeks are categories (not numbers) so every bar gets a real width.
        Chart(bars) { bar in
            BarMark(x: .value("Week", bar.label), y: .value("Pay", bar.amount * reveal), width: .ratio(0.6))
                .foregroundStyle(bar.isPaid ? Theme.ink : Theme.muted.opacity(0.3))
                .cornerRadius(3)
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel { Text(MoneyFormat.whole(value.as(Double.self) ?? 0)) }
            }
        }
        // Grows to fill the card when the card beside it is taller.
        .frame(minHeight: 180, maxHeight: .infinity)
        .accessibilityLabel("Pay for each week of the summer job")
    }

    private func key(fill: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func stat(_ label: String, _ value: String, _ number: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Theme.muted)
            Text(value).fontWeight(.semibold).monospacedDigit().animatedNumber(number)
        }
        .font(.caption)
    }
}

struct EntryRow: View {
    let entry: MoneyEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).fontWeight(.medium)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let bucket = entry.bucket {
                HStack(spacing: 6) {
                    BucketDot(bucket: bucket)
                    Text(bucket.name).font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(width: 90, alignment: .leading)
            }
            Text(amountText)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var amountText: String {
        switch entry.kind {
        case .paycheck, .allowance: MoneyFormat.signed(entry.amount)
        case .transfer: MoneyFormat.string(entry.amount)
        case .spending, .gas: MoneyFormat.signed(-entry.amount)
        }
    }
}
