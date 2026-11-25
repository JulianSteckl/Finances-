import XCTest

final class QuickLogTests: XCTestCase {
    func testReadsWholeDollars() { XCTAssertEqual(QuickLog.amount(from: "12"), 12) }
    func testReadsCents() { XCTAssertEqual(QuickLog.amount(from: "12.5"), 12.5) }
    func testReadsDollarSign() { XCTAssertEqual(QuickLog.amount(from: "$12.50"), 12.5) }
    func testReadsLeadingPoint() { XCTAssertEqual(QuickLog.amount(from: ".75"), 0.75) }
    func testReadsThousands() { XCTAssertEqual(QuickLog.amount(from: "1,234.56"), 1234.56) }
    func testIgnoresSpaces() { XCTAssertEqual(QuickLog.amount(from: "  8 "), 8) }
    func testCommaDecimalIsRejectedNotReadAsHundreds() { XCTAssertNil(QuickLog.amount(from: "12,50")) }
    func testWordsAreRejected() { XCTAssertNil(QuickLog.amount(from: "lunch")) }
    func testNegativeIsRejected() { XCTAssertNil(QuickLog.amount(from: "-5")) }
    func testZeroIsRejected() { XCTAssertNil(QuickLog.amount(from: "0")) }
    func testEmptyIsRejected() { XCTAssertNil(QuickLog.amount(from: "")) }
    func testLonePointIsRejected() { XCTAssertNil(QuickLog.amount(from: "$.")) }
    func testThreeDecimalsAreRejected() { XCTAssertNil(QuickLog.amount(from: "1.234")) }

    func testMenuBarRoundsDown() { XCTAssertEqual(QuickLog.menuBarText(left: 81.99), MoneyFormat.whole(81)) }
    func testMenuBarKeepsExactDollars() { XCTAssertEqual(QuickLog.menuBarText(left: 20 - 1e-9), MoneyFormat.whole(20)) }
    func testMenuBarShowsZero() { XCTAssertEqual(QuickLog.menuBarText(left: 0.4), MoneyFormat.whole(0)) }
    func testMenuBarShowsOverspending() { XCTAssertEqual(QuickLog.menuBarText(left: -10), MoneyFormat.whole(-10)) }

    func testEntryTrimsTheNote() {
        XCTAssertEqual(QuickLog.entry(kind: .spending, amount: 5, note: " Lunch ").note, "Lunch")
    }
}
