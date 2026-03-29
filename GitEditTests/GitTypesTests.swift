import XCTest
@testable import GitEditCore

final class GitTypesTests: XCTestCase {

    // MARK: - GutterKind shape names (accessibility: not color-only)

    func testGutterKindShapeNames() {
        XCTAssertEqual(GutterKind.added.shapeName, "plus")
        XCTAssertEqual(GutterKind.modified.shapeName, "circle.fill")
        XCTAssertEqual(GutterKind.deleted.shapeName, "minus")
    }

    func testGutterKindColorNames() {
        XCTAssertEqual(GutterKind.added.colorName, "systemGreen")
        XCTAssertEqual(GutterKind.modified.colorName, "systemOrange")
        XCTAssertEqual(GutterKind.deleted.colorName, "systemRed")
    }

    func testAllGutterKindsHaveDistinctShapes() {
        let shapes = GutterKind.allCases.map { $0.shapeName }
        XCTAssertEqual(shapes.count, Set(shapes).count, "Each GutterKind must have a unique shape for accessibility")
    }

    // MARK: - GutterIndicator

    func testGutterIndicatorInitAssignsUUID() {
        let a = GutterIndicator(lineRange: 1..<5, kind: .added)
        let b = GutterIndicator(lineRange: 1..<5, kind: .added)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testGutterIndicatorLineRange() {
        let indicator = GutterIndicator(lineRange: 10..<20, kind: .modified)
        XCTAssertEqual(indicator.lineRange, 10..<20)
        XCTAssertEqual(indicator.kind, .modified)
    }

    // MARK: - FileCommit

    func testFileCommitShortHash() {
        let commit = FileCommit(
            id: "abc1234567890",
            author: "Alice",
            email: "alice@example.com",
            message: "Initial commit",
            date: Date()
        )
        XCTAssertEqual(commit.shortHash, "abc1234")
    }

    func testFileCommitShortHashForShortId() {
        let commit = FileCommit(
            id: "abc",
            author: "Bob",
            email: "bob@example.com",
            message: "Tiny hash",
            date: Date()
        )
        XCTAssertEqual(commit.shortHash, "abc")
    }

    func testFileCommitRelativeDateIsNonEmpty() {
        let commit = FileCommit(
            id: "deadbeef1234567",
            author: "Carol",
            email: "carol@example.com",
            message: "Fix bug",
            date: Date(timeIntervalSinceNow: -3600) // 1 hour ago
        )
        XCTAssertFalse(commit.relativeDate.isEmpty)
    }

    // MARK: - BlameLine

    func testBlameLineShortHash() {
        let line = BlameLine(
            lineNumber: 42,
            commitHash: "feedface9876543",
            author: "Dave",
            date: Date(),
            message: "Refactor"
        )
        XCTAssertEqual(line.shortHash, "feedfac")
        XCTAssertEqual(line.id, 42)
    }

    // MARK: - DiffHunk / DiffLine

    func testDiffHunkInitAssignsUUID() {
        let h1 = DiffHunk(oldStart: 1, oldCount: 3, newStart: 1, newCount: 4, lines: [])
        let h2 = DiffHunk(oldStart: 1, oldCount: 3, newStart: 1, newCount: 4, lines: [])
        XCTAssertNotEqual(h1.id, h2.id)
    }

    func testDiffLineKinds() {
        let added = DiffLine(content: "+new line", kind: .added)
        let removed = DiffLine(content: "-old line", kind: .removed)
        let context = DiffLine(content: " unchanged", kind: .context)

        XCTAssertEqual(added.kind, .added)
        XCTAssertEqual(removed.kind, .removed)
        XCTAssertEqual(context.kind, .context)
    }

    // MARK: - GitFileStatus decoration colors

    func testGitFileStatusDecorationColors() {
        XCTAssertNil(GitFileStatus.unmodified.decorationColorName)
        XCTAssertNil(GitFileStatus.ignored.decorationColorName)
        XCTAssertEqual(GitFileStatus.modified.decorationColorName, "systemOrange")
        XCTAssertEqual(GitFileStatus.added.decorationColorName, "systemGreen")
        XCTAssertEqual(GitFileStatus.untracked.decorationColorName, "systemGreen")
        XCTAssertEqual(GitFileStatus.deleted.decorationColorName, "systemRed")
        XCTAssertEqual(GitFileStatus.renamed.decorationColorName, "systemBlue")
    }
}

// Make GutterKind CaseIterable for the distinctness test
extension GutterKind: CaseIterable {
    public static var allCases: [GutterKind] { [.added, .modified, .deleted] }
}
