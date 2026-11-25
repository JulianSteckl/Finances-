import Foundation
import SwiftData

/// Everything the app stores, as one file.
struct Backup: Codable, Equatable {
    static let currentVersion = 1

    var version = Backup.currentVersion
    var savedAt: Date
    var plan: Plan?
    var entries: [Entry]

    struct Plan: Codable, Equatable {
        var hoursPerWeek: Double
        var hourlyWage: Double
        var weeksInSeason: Double
        var totalTargetOverride: Double
        var updatedAt: Date
        var usesSeasonDates: Bool
        var seasonStart: Date
        var seasonEnd: Date
        var payFrequencyRaw: String
        var overtimeHoursPerWeek: Double
        var overtimeMultiplier: Double
        var tipsPerWeek: Double
        var oneTimeBonuses: Double
        var allowancePerWeek: Double
        var spendingPerWeek: Double
        var gasPerTwoWeeks: Double
        var savingsGoal: Double
        var startingMoney: Double
        var taxRate: Double
        var stockReturn: Double
        var savingsReturn: Double
        var jobStart: Date?
        var allowanceWeekday: Int?
        var allowanceLoggedThrough: Date?
    }

    struct Entry: Codable, Equatable {
        var amount: Double
        var date: Date
        var note: String
        var kindRaw: String
        var createdAt: Date
        var entryID: UUID
        var bucketRaw: String?
        var hours: Double
        var linkedPaycheckID: UUID?
        var spendingCategoryRaw: String?
    }

    enum Problem: LocalizedError {
        case notABackup
        case newerVersion
        case badEntry

        var errorDescription: String? {
            switch self {
            case .notABackup: "That file isn't a Finances backup."
            case .newerVersion: "That backup was made by a newer version of Finances."
            case .badEntry: "That backup has an entry Finances can't read, so nothing was changed."
            }
        }
    }
}

// MARK: - Reading and writing

extension Backup {
    @MainActor
    init(context: ModelContext, now: Date = .now) throws {
        savedAt = now
        plan = try context.fetch(FetchDescriptor<IncomePlan>()).first.map(Plan.init)
        entries = try context.fetch(FetchDescriptor<MoneyEntry>(sortBy: [SortDescriptor(\.date)])).map(Entry.init)
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Checks the whole file before anything is changed.
    init(data: Data) throws {
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw Problem.notABackup }
        guard header.version <= Self.currentVersion else { throw Problem.newerVersion }
        guard let backup = try? decoder.decode(Backup.self, from: data) else { throw Problem.notABackup }
        guard backup.entries.allSatisfy(\.isReadable) else { throw Problem.badEntry }
        self = backup
    }

    /// Replaces the plan and every entry. If saving fails, nothing changes.
    @MainActor
    func restore(into context: ModelContext) throws {
        do {
            if let plan {
                let target = try context.fetch(FetchDescriptor<IncomePlan>()).first ?? {
                    let created = IncomePlan()
                    context.insert(created)
                    return created
                }()
                plan.apply(to: target)
                // Tells open screens to reload, even if the restored plan has the same date.
                target.updatedAt = .now
            }
            try context.fetch(FetchDescriptor<MoneyEntry>()).forEach(context.delete)
            entries.map(\.model).forEach(context.insert)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension Backup.Plan {
    init(_ plan: IncomePlan) {
        self.init(
            hoursPerWeek: plan.hoursPerWeek, hourlyWage: plan.hourlyWage, weeksInSeason: plan.weeksInSeason,
            totalTargetOverride: plan.totalTargetOverride, updatedAt: plan.updatedAt,
            usesSeasonDates: plan.usesSeasonDates, seasonStart: plan.seasonStart, seasonEnd: plan.seasonEnd,
            payFrequencyRaw: plan.payFrequencyRaw, overtimeHoursPerWeek: plan.overtimeHoursPerWeek,
            overtimeMultiplier: plan.overtimeMultiplier, tipsPerWeek: plan.tipsPerWeek, oneTimeBonuses: plan.oneTimeBonuses,
            allowancePerWeek: plan.allowancePerWeek, spendingPerWeek: plan.spendingPerWeek,
            gasPerTwoWeeks: plan.gasPerTwoWeeks, savingsGoal: plan.savingsGoal, startingMoney: plan.startingMoney,
            taxRate: plan.taxRate, stockReturn: plan.stockReturn, savingsReturn: plan.savingsReturn,
            jobStart: plan.jobStart, allowanceWeekday: plan.allowanceWeekday,
            allowanceLoggedThrough: plan.allowanceLoggedThrough
        )
    }

    func apply(to plan: IncomePlan) {
        plan.hoursPerWeek = hoursPerWeek
        plan.hourlyWage = hourlyWage
        plan.weeksInSeason = weeksInSeason
        plan.totalTargetOverride = totalTargetOverride
        plan.updatedAt = updatedAt
        plan.usesSeasonDates = usesSeasonDates
        plan.seasonStart = seasonStart
        plan.seasonEnd = seasonEnd
        plan.payFrequencyRaw = payFrequencyRaw
        plan.overtimeHoursPerWeek = overtimeHoursPerWeek
        plan.overtimeMultiplier = overtimeMultiplier
        plan.tipsPerWeek = tipsPerWeek
        plan.oneTimeBonuses = oneTimeBonuses
        plan.allowancePerWeek = allowancePerWeek
        plan.spendingPerWeek = spendingPerWeek
        plan.gasPerTwoWeeks = gasPerTwoWeeks
        plan.savingsGoal = savingsGoal
        plan.startingMoney = startingMoney
        plan.taxRate = taxRate
        plan.stockReturn = stockReturn
        plan.savingsReturn = savingsReturn
        plan.jobStart = jobStart
        plan.allowanceWeekday = allowanceWeekday
        plan.allowanceLoggedThrough = allowanceLoggedThrough
    }
}

extension Backup.Entry {
    init(_ entry: MoneyEntry) {
        self.init(
            amount: entry.amount, date: entry.date, note: entry.note, kindRaw: entry.kindRaw, createdAt: entry.createdAt,
            entryID: entry.entryID, bucketRaw: entry.bucketRaw, hours: entry.hours, linkedPaycheckID: entry.linkedPaycheckID,
            spendingCategoryRaw: entry.spendingCategoryRaw
        )
    }

    /// Unknown kinds would otherwise be read as purchases.
    var isReadable: Bool {
        guard let kind = EntryKind(rawValue: kindRaw), amount.isFinite, amount >= 0 else { return false }
        return kind != .transfer || bucketRaw.flatMap(Bucket.init(rawValue:)) != nil
    }

    var model: MoneyEntry {
        let entry = MoneyEntry(
            amount: amount, date: date, note: note, kind: EntryKind(rawValue: kindRaw) ?? .spending,
            hours: hours, linkedPaycheckID: linkedPaycheckID, createdAt: createdAt
        )
        entry.bucketRaw = bucketRaw
        entry.entryID = entryID
        entry.spendingCategoryRaw = spendingCategoryRaw
        return entry
    }
}

// MARK: - Spreadsheet

/// The log as a spreadsheet file, newest first.
enum LogExport {
    private static let header = "Date,Type,Description,Category,Bucket,Amount,Hours"
    /// Lets Excel read accents and symbols correctly.
    private static let byteOrderMark = "\u{FEFF}"
    private static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    static func csv(_ entries: [MoneyEntry], calendar: Calendar = .current) -> String {
        let rows = entries.sorted { $0.date > $1.date }.map { entry in
            [day(entry.date, calendar: calendar), entry.kind.label, cell(entry.title), entry.spendingCategory?.name ?? "", entry.bucket?.name ?? "",
             number(signedAmount(entry)), entry.hours > 0 ? number(entry.hours) : ""].joined(separator: ",")
        }
        return byteOrderMark + ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }

    /// Spending and gas are negative; pay, allowance and moves are positive.
    private static func signedAmount(_ entry: MoneyEntry) -> Double {
        entry.kind == .spending || entry.kind == .gas ? -entry.amount : entry.amount
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Quoted so commas and quotes survive, and never run as a spreadsheet formula.
    private static func cell(_ text: String) -> String {
        let safe = text.first.map(formulaStarts.contains) == true ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
