import XCTest
@testable import GitEditCore

final class EnvParserTests: XCTestCase {

    let parser = EnvParser()

    // MARK: - Basic parsing

    func testParseKeyValue() {
        let entries = parser.parse("DATABASE_URL=postgres://localhost/db")
        XCTAssertEqual(entries.count, 1)
        if case .keyValue(let key, let value, _) = entries[0].kind {
            XCTAssertEqual(key, "DATABASE_URL")
            XCTAssertEqual(value, "postgres://localhost/db")
        } else {
            XCTFail("Expected keyValue")
        }
    }

    func testParseComment() {
        let entries = parser.parse("# This is a comment")
        XCTAssertEqual(entries.count, 1)
        if case .comment(let text) = entries[0].kind {
            XCTAssertEqual(text, "# This is a comment")
        } else {
            XCTFail("Expected comment")
        }
    }

    func testParseBlankLine() {
        let entries = parser.parse("\n\n")
        XCTAssertTrue(entries.contains { if case .blank = $0.kind { return true }; return false })
    }

    func testMultipleEntries() {
        let content = """
        # Config
        APP_NAME=GitEdit
        PORT=3000
        """
        let entries = parser.parse(content)
        let kvEntries = entries.filter { if case .keyValue = $0.kind { return true }; return false }
        XCTAssertEqual(kvEntries.count, 2)
    }

    // MARK: - Quoted values

    func testDoubleQuotedValue() {
        let entries = parser.parse("KEY=\"hello world\"")
        if case .keyValue(_, let value, _) = entries[0].kind {
            XCTAssertEqual(value, "hello world")
        } else {
            XCTFail("Expected keyValue")
        }
    }

    func testSingleQuotedValue() {
        let entries = parser.parse("KEY='hello world'")
        if case .keyValue(_, let value, _) = entries[0].kind {
            XCTAssertEqual(value, "hello world")
        } else {
            XCTFail("Expected keyValue")
        }
    }

    // MARK: - Secret detection

    func testSensitiveKeyDetection() {
        XCTAssertTrue(EnvParser.isSensitiveKey("DATABASE_PASSWORD"))
        XCTAssertTrue(EnvParser.isSensitiveKey("API_SECRET"))
        XCTAssertTrue(EnvParser.isSensitiveKey("ACCESS_TOKEN"))
        XCTAssertTrue(EnvParser.isSensitiveKey("PRIVATE_KEY"))
        XCTAssertTrue(EnvParser.isSensitiveKey("AWS_SECRET_ACCESS_KEY"))
        XCTAssertTrue(EnvParser.isSensitiveKey("AUTH_CREDENTIAL"))
    }

    func testNonSensitiveKeys() {
        XCTAssertFalse(EnvParser.isSensitiveKey("APP_NAME"))
        XCTAssertFalse(EnvParser.isSensitiveKey("PORT"))
        XCTAssertFalse(EnvParser.isSensitiveKey("DATABASE_URL"))
        XCTAssertFalse(EnvParser.isSensitiveKey("NODE_ENV"))
    }

    func testSensitiveFlagInParsedEntry() {
        let entries = parser.parse("SECRET_KEY=abc123")
        if case .keyValue(_, _, let isSensitive) = entries[0].kind {
            XCTAssertTrue(isSensitive)
        } else {
            XCTFail("Expected keyValue")
        }
    }

    // MARK: - Edge cases

    func testEmptyValue() {
        let entries = parser.parse("EMPTY=")
        if case .keyValue(let key, let value, _) = entries[0].kind {
            XCTAssertEqual(key, "EMPTY")
            XCTAssertEqual(value, "")
        } else {
            XCTFail("Expected keyValue")
        }
    }

    func testValueWithEquals() {
        let entries = parser.parse("URL=postgres://host?opt=1")
        if case .keyValue(_, let value, _) = entries[0].kind {
            XCTAssertEqual(value, "postgres://host?opt=1")
        } else {
            XCTFail("Expected keyValue")
        }
    }

    func testLineNumbers() {
        let entries = parser.parse("A=1\nB=2\nC=3")
        XCTAssertEqual(entries[0].lineNumber, 0)
        XCTAssertEqual(entries[1].lineNumber, 1)
        XCTAssertEqual(entries[2].lineNumber, 2)
    }

    func testMalformedLineWithNoEqualsIsTreatedAsComment() {
        // Design spec: malformed lines (no `=`) fall back to comment display
        let entries = parser.parse("NOT_A_VALID_LINE")
        XCTAssertEqual(entries.count, 1)
        if case .comment = entries[0].kind {
            // correct
        } else {
            XCTFail("Malformed line should be treated as comment, got \(entries[0].kind)")
        }
    }

    func testEmptyInput() {
        let entries = parser.parse("")
        // Empty string splits into one empty component — one blank entry
        XCTAssertEqual(entries.count, 1)
        if case .blank = entries[0].kind { } else {
            XCTFail("Empty input should produce a blank entry")
        }
    }

    // MARK: - isSensitiveKey edge cases

    func testSensitiveKeyIsCaseInsensitive() {
        XCTAssertTrue(EnvParser.isSensitiveKey("database_password"))
        XCTAssertTrue(EnvParser.isSensitiveKey("Api_Secret"))
    }

    func testNonSensitiveKeyWithSimilarSubstring() {
        // "MONKEY_PATCH" should NOT be flagged — "KEY" must match a full underscore-delimited component
        XCTAssertFalse(EnvParser.isSensitiveKey("MONKEY_PATCH"))
        XCTAssertFalse(EnvParser.isSensitiveKey("DONKEY_WORK"))
        // But "API_KEY" should still match
        XCTAssertTrue(EnvParser.isSensitiveKey("API_KEY"))
    }
}
