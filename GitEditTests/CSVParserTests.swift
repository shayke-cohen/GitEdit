import XCTest
@testable import GitEditCore

final class CSVParserTests: XCTestCase {

    let parser = CSVParser()

    // MARK: - Basic parsing

    func testParseSimpleCSV() {
        let csv = "name,age\nAlice,30\nBob,25"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.headers, ["name", "age"])
        XCTAssertEqual(doc.rowCount, 2)
        XCTAssertEqual(doc.rows[0], ["Alice", "30"])
        XCTAssertEqual(doc.rows[1], ["Bob", "25"])
    }

    func testParseTSV() {
        let tsv = "name\tage\nAlice\t30"
        let doc = parser.parse(tsv, delimiter: "\t")
        XCTAssertEqual(doc.headers, ["name", "age"])
        XCTAssertEqual(doc.rows[0], ["Alice", "30"])
    }

    // MARK: - Quoted fields

    func testQuotedFieldWithComma() {
        let csv = "name,address\n\"Doe, Jane\",\"123 Main St\""
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.rows[0][0], "Doe, Jane")
    }

    func testEscapedQuote() {
        let csv = "col\n\"She said \"\"hello\"\"\""
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.rows[0][0], "She said \"hello\"")
    }

    // MARK: - Edge cases

    func testEmptyContent() {
        let doc = parser.parse("")
        XCTAssertEqual(doc.headers, [])
        XCTAssertEqual(doc.rowCount, 0)
    }

    func testHeaderOnly() {
        let doc = parser.parse("a,b,c")
        XCTAssertEqual(doc.headers, ["a", "b", "c"])
        XCTAssertEqual(doc.rowCount, 0)
    }

    func testEmptyCells() {
        let csv = "a,b,c\n,,\n1,,3"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.rows[0], ["", "", ""])
        XCTAssertEqual(doc.rows[1], ["1", "", "3"])
    }

    func testUnicodeContent() {
        let csv = "emoji,text\n🌿,日本語"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.rows[0][0], "🌿")
        XCTAssertEqual(doc.rows[0][1], "日本語")
    }

    func testWindowsLineEndings() {
        let csv = "a,b\r\n1,2\r\n3,4"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.rowCount, 2)
        XCTAssertEqual(doc.rows[0], ["1", "2"])
    }

    // MARK: - Column type inference

    func testInferNumberColumn() {
        let csv = "val\n1\n2.5\n-3\n100"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.columnTypes.first, .number)
    }

    func testInferTextColumn() {
        let csv = "name\nAlice\nBob\nCharlie"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.columnTypes.first, .text)
    }

    func testInferDateColumn() {
        let csv = "date\n2024-01-15\n2024-02-20\n2024-03-25\n2024-04-30\n2024-05-05"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.columnTypes.first, .date)
    }

    func testColumnCount() {
        let csv = "a,b,c\n1,2,3"
        let doc = parser.parse(csv)
        XCTAssertEqual(doc.columnCount, 3)
    }
}
