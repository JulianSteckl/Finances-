import SwiftData
import XCTest

@MainActor
final class BackupTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let schema = Schema([IncomePlan.self, BudgetCategory.self, MoneyEntry.self])
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000.123456)

    override func setUpWithError() throws { container = try makeContainer() }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)])
    }

    private func addSampleData() {
        let plan = IncomePlan(hoursPerWeek: 31, hourlyWage: 22, weeksInSeason: 11)
        plan.jobStart = date
        plan.allowanceWeekday = 3
        plan.allowanceLoggedThrough = date
        plan.savingsGoal = 1234
        plan.taxRate = 0.08
        context.insert(plan)
        let paycheck = MoneyEntry(amount: 590.25, date: date, kind: .paycheck, hours: 29.5, createdAt: date)
        context.insert(paycheck)
        context.insert(MoneyEntry(amount: 100, date: date, kind: .transfer, bucket: .stocks, linkedPaycheckID: paycheck.entryID, createdAt: date))
        context.insert(MoneyEntry(amount: 12.5, date: date, note: "Lunch, \"big\"", kind: .spending, createdAt: date))
    }

    private func sorted(_ backup: Backup) -> [Backup.Entry] { backup.entries.sorted { $0.amount < $1.amount } }

    // MARK: Coverage: a new stored value must be added to the backup

    private func storedNames(_ entity: String) -> Set<String> {
        Set(schema.entities.first { $0.name == entity }!.attributes.map(\.name))
    }

    private func names(_ value: Any) -> Set<String> { Set(Mirror(reflecting: value).children.compactMap(\.label)) }

    func testEveryPlanValueIsBackedUp() {
        XCTAssertEqual(names(Backup.Plan(IncomePlan())), storedNames("IncomePlan"))
    }

    func testEveryEntryValueIsBackedUp() {
        XCTAssertEqual(names(Backup.Entry(MoneyEntry(amount: 1, kind: .gas))), storedNames("MoneyEntry"))
    }

    // MARK: Round trip

    func testRestoringIntoAnEmptyAppBringsBackEveryEntry() throws {
        addSampleData()
        let backup = try Backup(data: Backup(context: context).data())
        let empty = try makeContainer()
        try backup.restore(into: empty.mainContext)
        XCTAssertEqual(sorted(try Backup(context: empty.mainContext)), sorted(backup))
    }

    func testRestoringIntoAnEmptyAppBringsBackThePlan() throws {
        addSampleData()
        let backup = try Backup(data: Backup(context: context).data())
        let empty = try makeContainer()
        try backup.restore(into: empty.mainContext)
        var restored = try XCTUnwrap(Backup(context: empty.mainContext).plan)
        restored.updatedAt = try XCTUnwrap(backup.plan).updatedAt
        XCTAssertEqual(restored, backup.plan)
    }

    func testRestoreReplacesInsteadOfAdding() throws {
        addSampleData()
        let backup = try Backup(context: context)
        context.insert(MoneyEntry(amount: 999, kind: .spending))
        try backup.restore(into: context)
        XCTAssertEqual(sorted(try Backup(context: context)), sorted(backup))
    }

    func testRestoreKeepsOnePlan() throws {
        addSampleData()
        try Backup(context: context).restore(into: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<IncomePlan>()).count, 1)
    }

    func testBalancesMatchAfterRestore() throws {
        addSampleData()
        let before = Ledger(entries: try context.fetch(FetchDescriptor<MoneyEntry>())).balance(of: .stocks)
        try Backup(context: context).restore(into: context)
        XCTAssertEqual(Ledger(entries: try context.fetch(FetchDescriptor<MoneyEntry>())).balance(of: .stocks), before)
    }

    // MARK: Bad files

    private func change(_ edit: (inout Backup) -> Void) throws -> Data {
        addSampleData()
        var backup = try Backup(context: context)
        edit(&backup)
        return try backup.data()
    }

    func testRejectsOtherFiles() { XCTAssertThrowsError(try Backup(data: Data("hello".utf8))) }
    func testRejectsOtherJSON() { XCTAssertThrowsError(try Backup(data: Data(#"{"version": 1}"#.utf8))) }
    func testRejectsNewerVersions() throws { XCTAssertThrowsError(try Backup(data: change { $0.version = 2 })) }
    func testRejectsUnknownKinds() throws { XCTAssertThrowsError(try Backup(data: change { $0.entries[0].kindRaw = "loan" })) }
    func testRejectsNegativeAmounts() throws { XCTAssertThrowsError(try Backup(data: change { $0.entries[0].amount = -5 })) }

    func testRejectsMovesWithoutABucket() throws {
        XCTAssertThrowsError(try Backup(data: change { backup in
            let index = backup.entries.firstIndex { $0.kindRaw == "transfer" }!
            backup.entries[index].bucketRaw = nil
        }))
    }

    // MARK: Spreadsheet

    private func rows(_ entries: [MoneyEntry]) -> [String] {
        LogExport.csv(entries).components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    func testSpreadsheetHasAHeaderAndARowPerEntry() {
        XCTAssertEqual(rows([MoneyEntry(amount: 1, kind: .gas), MoneyEntry(amount: 2, kind: .gas)]).count, 3)
    }

    func testPurchaseRow() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
        XCTAssertEqual(rows([MoneyEntry(amount: 12.5, date: day, note: "Lunch", kind: .spending)])[1], "2026-11-24,Spending,\"Lunch\",Spending,-12.50,")
    }

    func testCommasAndQuotesSurvive() {
        XCTAssertTrue(rows([MoneyEntry(amount: 1, note: "A, \"B\"", kind: .spending)])[1].contains("\"A, \"\"B\"\"\""))
    }

    func testNotesCannotRunAsFormulas() {
        XCTAssertTrue(rows([MoneyEntry(amount: 1, note: "=SUM(A1)", kind: .spending)])[1].contains("\"'=SUM(A1)\""))
    }
}
