import XCTest
@testable import GitEditCore

final class FileTypeTests: XCTestCase {

    // MARK: - Extension-based detection

    func testMarkdownExtensions() {
        XCTAssertEqual(FileType.detect(from: url("README.md")), .markdown)
        XCTAssertEqual(FileType.detect(from: url("page.mdx")), .markdown)
        XCTAssertEqual(FileType.detect(from: url("notes.markdown")), .markdown)
    }

    func testCSVExtension() {
        XCTAssertEqual(FileType.detect(from: url("data.csv")), .csv)
    }

    func testTSVExtension() {
        XCTAssertEqual(FileType.detect(from: url("data.tsv")), .tsv)
    }

    func testJSONExtension() {
        XCTAssertEqual(FileType.detect(from: url("config.json")), .json)
    }

    func testYAMLExtensions() {
        XCTAssertEqual(FileType.detect(from: url("deploy.yaml")), .yaml)
        XCTAssertEqual(FileType.detect(from: url("deploy.yml")), .yaml)
    }

    func testTOMLExtension() {
        XCTAssertEqual(FileType.detect(from: url("Cargo.toml")), .toml)
    }

    func testPlainTextExtensions() {
        XCTAssertEqual(FileType.detect(from: url("notes.txt")), .plainText)
        XCTAssertEqual(FileType.detect(from: url("LICENSE")), .plainText)
        XCTAssertEqual(FileType.detect(from: url("unknown.xyz")), .plainText)
    }

    // MARK: - Name-based .env detection

    func testDotEnvExact() {
        XCTAssertEqual(FileType.detect(from: url(".env")), .env)
    }

    func testDotEnvWithSuffix() {
        XCTAssertEqual(FileType.detect(from: url(".env.local")), .env)
        XCTAssertEqual(FileType.detect(from: url(".env.production")), .env)
        XCTAssertEqual(FileType.detect(from: url(".env.test")), .env)
    }

    func testDotEnvExtension() {
        // file named "secrets.env" should also resolve to .env
        XCTAssertEqual(FileType.detect(from: url("secrets.env")), .env)
    }

    // MARK: - Case insensitivity

    func testUppercaseExtension() {
        XCTAssertEqual(FileType.detect(from: url("DATA.CSV")), .csv)
        XCTAssertEqual(FileType.detect(from: url("README.MD")), .markdown)
    }

    // MARK: - Rendering mode mapping

    func testRenderingModes() {
        XCTAssertEqual(FileType.markdown.renderingMode, .splitPreview)
        XCTAssertEqual(FileType.csv.renderingMode, .table)
        XCTAssertEqual(FileType.tsv.renderingMode, .table)
        XCTAssertEqual(FileType.json.renderingMode, .tree)
        XCTAssertEqual(FileType.yaml.renderingMode, .tree)
        XCTAssertEqual(FileType.toml.renderingMode, .tree)
        XCTAssertEqual(FileType.env.renderingMode, .keyValue)
        XCTAssertEqual(FileType.plainText.renderingMode, .prose)
    }

    // MARK: - Display names (non-empty)

    func testDisplayNamesAreNonEmpty() {
        for type in FileType.allCases {
            XCTAssertFalse(type.displayName.isEmpty, "\(type) has empty displayName")
        }
    }

    // MARK: - Icon names (non-empty)

    func testIconNamesAreNonEmpty() {
        for type in FileType.allCases {
            XCTAssertFalse(type.iconName.isEmpty, "\(type) has empty iconName")
        }
    }

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }
}
