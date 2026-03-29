import XCTest
@testable import GitEditCore

final class EditorTabTests: XCTestCase {

    // MARK: - File type detection from URL

    func testMarkdownTabFileType() {
        let tab = EditorTab(url: url("README.md"))
        XCTAssertEqual(tab.fileType, .markdown)
    }

    func testCSVTabFileType() {
        let tab = EditorTab(url: url("data.csv"))
        XCTAssertEqual(tab.fileType, .csv)
    }

    func testEnvTabFileType() {
        let tab = EditorTab(url: url(".env"))
        XCTAssertEqual(tab.fileType, .env)
    }

    // MARK: - Default view mode per file type (design spec: markdown defaults to split)

    func testMarkdownDefaultsToSplitMode() {
        let tab = EditorTab(url: url("notes.md"))
        XCTAssertEqual(tab.viewMode, .split,
            "Markdown must default to split view per design spec")
    }

    func testCSVDefaultsToRenderedMode() {
        let tab = EditorTab(url: url("data.csv"))
        XCTAssertEqual(tab.viewMode, .rendered,
            "CSV must default to table (rendered) view")
    }

    func testJSONDefaultsToRenderedMode() {
        let tab = EditorTab(url: url("config.json"))
        XCTAssertEqual(tab.viewMode, .rendered)
    }

    func testEnvDefaultsToRenderedMode() {
        let tab = EditorTab(url: url(".env.local"))
        XCTAssertEqual(tab.viewMode, .rendered)
    }

    func testPlainTextDefaultsToRenderedMode() {
        let tab = EditorTab(url: url("notes.txt"))
        XCTAssertEqual(tab.viewMode, .rendered)
    }

    // MARK: - Initial state

    func testNewTabIsNotModified() {
        let tab = EditorTab(url: url("file.md"))
        XCTAssertFalse(tab.isModified)
    }

    func testNewTabHasEmptyContentByDefault() {
        let tab = EditorTab(url: url("file.md"))
        XCTAssertEqual(tab.content, "")
    }

    func testTabInitWithContent() {
        let tab = EditorTab(url: url("file.txt"), content: "Hello world")
        XCTAssertEqual(tab.content, "Hello world")
    }

    // MARK: - Name derived from URL

    func testTabNameFromURL() {
        let tab = EditorTab(url: url("my-document.md"))
        XCTAssertEqual(tab.name, "my-document.md")
    }

    func testDotEnvTabName() {
        let tab = EditorTab(url: url(".env"))
        XCTAssertEqual(tab.name, ".env")
    }

    // MARK: - Unique IDs

    func testTabsHaveUniqueIDs() {
        let a = EditorTab(url: url("file.md"))
        let b = EditorTab(url: url("file.md"))
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }
}
