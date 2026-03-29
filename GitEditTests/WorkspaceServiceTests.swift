import XCTest
@testable import GitEditCore

final class WorkspaceServiceTests: XCTestCase {

    var service: WorkspaceService!
    var tempDir: URL!

    override func setUp() async throws {
        service = WorkspaceService()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitEditTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - scanDirectory

    func testScanReturnsFiles() async throws {
        try "hello".write(to: tempDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "# Title".write(to: tempDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let items = try await MainActor.run {
            try service.scanDirectory(at: tempDir)
        }

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { !$0.isDirectory })
    }

    func testScanSortsDirectoriesFirst() async throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("subdir"), withIntermediateDirectories: true)
        try "".write(to: tempDir.appendingPathComponent("aaa.txt"), atomically: true, encoding: .utf8)

        let items = try await MainActor.run {
            try service.scanDirectory(at: tempDir)
        }

        XCTAssertTrue(items.first!.isDirectory, "Directories should sort before files")
    }

    func testScanSkipsHiddenFiles() async throws {
        try "visible".write(to: tempDir.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: tempDir.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        let items = try await MainActor.run {
            try service.scanDirectory(at: tempDir)
        }

        XCTAssertFalse(items.contains { $0.name == ".hidden" }, ".hidden should be skipped")
        XCTAssertTrue(items.contains { $0.name == "visible.txt" })
    }

    func testScanIncludesDotEnv() async throws {
        try "KEY=value".write(to: tempDir.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "KEY=value".write(to: tempDir.appendingPathComponent(".env.local"), atomically: true, encoding: .utf8)

        let items = try await MainActor.run {
            try service.scanDirectory(at: tempDir)
        }

        XCTAssertTrue(items.contains { $0.name == ".env" }, ".env must not be filtered out")
        XCTAssertTrue(items.contains { $0.name == ".env.local" }, ".env.local must not be filtered out")
    }

    func testScanAssignsCorrectFileType() async throws {
        try "".write(to: tempDir.appendingPathComponent("data.csv"), atomically: true, encoding: .utf8)

        let items = try await MainActor.run {
            try service.scanDirectory(at: tempDir)
        }

        XCTAssertEqual(items.first?.fileType, .csv)
    }

    func testScanEmptyDirectory() async throws {
        let items = try await MainActor.run {
            try service.scanDirectory(at: tempDir)
        }
        XCTAssertEqual(items.count, 0)
    }

    func testScanRespectsMaxDepth() async throws {
        // Create a 3-level deep structure
        let deep = tempDir
            .appendingPathComponent("a")
            .appendingPathComponent("b")
            .appendingPathComponent("c")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try "deep".write(to: deep.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let items = try await MainActor.run {
            try service.scanDirectory(at: tempDir, maxDepth: 1)
        }

        // With maxDepth: 1, we should see dir "a" but NOT its children
        let aDir = items.first { $0.name == "a" }
        XCTAssertNotNil(aDir)
        let aChildren = await MainActor.run { aDir?.children }
        XCTAssertEqual(aChildren?.count ?? 0, 0, "Should not recurse beyond maxDepth")
    }

    // MARK: - readFile / writeFile

    func testReadWriteRoundtrip() throws {
        let file = tempDir.appendingPathComponent("roundtrip.txt")
        let original = "Hello, GitEdit! 🌿"
        try service.writeFile(content: original, to: file)
        let read = try service.readFile(at: file)
        XCTAssertEqual(read, original)
    }

    func testReadMissingFileThrows() {
        let missing = tempDir.appendingPathComponent("ghost.txt")
        XCTAssertThrowsError(try service.readFile(at: missing))
    }

    // MARK: - fileSize

    func testFileSizeIsAccurate() throws {
        let file = tempDir.appendingPathComponent("sized.txt")
        let content = "abcde"  // 5 bytes in UTF-8
        try service.writeFile(content: content, to: file)
        let size = try service.fileSize(at: file)
        XCTAssertEqual(size, UInt64(content.utf8.count))
    }

    // MARK: - isInGitRepo / gitRepoRoot

    func testIsInGitRepoFalseForPlainDir() {
        XCTAssertFalse(service.isInGitRepo(url: tempDir))
    }

    func testIsInGitRepoTrueWhenDotGitExists() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let fileInRepo = tempDir.appendingPathComponent("file.md")
        XCTAssertTrue(service.isInGitRepo(url: fileInRepo))
    }

    func testGitRepoRootNilForPlainDir() {
        XCTAssertNil(service.gitRepoRoot(for: tempDir.appendingPathComponent("file.txt")))
    }

    func testGitRepoRootFindsRoot() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        let subDir = tempDir.appendingPathComponent("src").appendingPathComponent("models")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let deepFile = subDir.appendingPathComponent("User.swift")

        let root = service.gitRepoRoot(for: deepFile)
        XCTAssertEqual(root?.resolvingSymlinksInPath().path, tempDir.resolvingSymlinksInPath().path)
    }
}
