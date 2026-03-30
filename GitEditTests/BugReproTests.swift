import XCTest
@testable import GitEditCore

/// Regression tests for fixed bugs. These tests must PASS.
final class BugReproTests: XCTestCase {

    // MARK: - Bug #3 (fixed): StatusBarView row count for CSV with trailing newline
    // Fix: StatusBarView now uses CSVParser().parse(content).rowCount instead of
    //      content.components(separatedBy:.newlines).count - 1

    func testCSVRowCount_trailingNewline() {
        let content = "name,age\nAlice,30\n"  // header + 1 data row + trailing newline
        let rows = CSVParser().parse(content).rowCount
        XCTAssertEqual(rows, 1, "Trailing newline must not count as an extra row")
    }

    func testCSVRowCount_noTrailingNewline() {
        let content = "name,age\nAlice,30"
        let rows = CSVParser().parse(content).rowCount
        XCTAssertEqual(rows, 1)
    }

    func testCSVRowCount_multipleRows_trailingNewline() {
        let content = "name,age\nAlice,30\nBob,25\nCarol,40\n"  // 3 data rows + trailing newline
        let rows = CSVParser().parse(content).rowCount
        XCTAssertEqual(rows, 3, "3 data rows regardless of trailing newline")
    }

    // MARK: - Bug #4: EnvParser.isSensitiveKey false positives via substring matching

    /// "KEY" appears as a substring in "MONKEY", "TURKEY", "DONKEY", "HOCKEY"
    /// None of these should be flagged as sensitive.
    func testIsSensitiveKey_monkeyIsNotSensitive() {
        XCTAssertFalse(EnvParser.isSensitiveKey("MONKEY_DATA"),
            "BUG #4: MONKEY_DATA is not sensitive but 'KEY' substring causes false positive")
    }

    func testIsSensitiveKey_turkeyIsNotSensitive() {
        XCTAssertFalse(EnvParser.isSensitiveKey("TURKEY_COUNT"),
            "BUG #4: TURKEY_COUNT is not sensitive but 'KEY' substring causes false positive")
    }

    func testIsSensitiveKey_donkeyIsNotSensitive() {
        XCTAssertFalse(EnvParser.isSensitiveKey("DONKEY_ID"),
            "BUG #4: DONKEY_ID is not sensitive but 'KEY' substring causes false positive")
    }

    /// "AUTH" appears in "AUTHOR", "AUTHORITY" — not sensitive
    func testIsSensitiveKey_authorIsNotSensitive() {
        XCTAssertFalse(EnvParser.isSensitiveKey("AUTHOR_NAME"),
            "BUG #4: AUTHOR_NAME is not sensitive but 'AUTH' substring causes false positive")
    }

    /// Verify that genuinely sensitive keys still work
    func testIsSensitiveKey_truePositives() {
        XCTAssertTrue(EnvParser.isSensitiveKey("API_KEY"))
        XCTAssertTrue(EnvParser.isSensitiveKey("DB_PASSWORD"))
        XCTAssertTrue(EnvParser.isSensitiveKey("ACCESS_TOKEN"))
        XCTAssertTrue(EnvParser.isSensitiveKey("GITHUB_SECRET"))
        XCTAssertTrue(EnvParser.isSensitiveKey("OAUTH_TOKEN"))
    }
}
