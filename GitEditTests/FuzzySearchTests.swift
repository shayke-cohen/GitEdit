import XCTest
@testable import GitEditCore

final class FuzzySearchTests: XCTestCase {

    let search = FuzzySearch()

    func testExactMatchScoresHighest() {
        let score = search.score(query: "readme", candidate: "readme")
        XCTAssertNotNil(score)
        XCTAssertGreaterThan(score!, 0)
    }

    func testPrefixMatchBeatsMiddleMatch() {
        let prefixScore = search.score(query: "read", candidate: "readme.md")!
        let middleScore = search.score(query: "read", candidate: "unread.txt")!
        XCTAssertGreaterThan(prefixScore, middleScore)
    }

    func testNoMatchReturnsNil() {
        let score = search.score(query: "xyz", candidate: "readme.md")
        XCTAssertNil(score)
    }

    func testEmptyQueryMatchesEverything() {
        let score = search.score(query: "", candidate: "anything")
        XCTAssertEqual(score, 0)
    }

    func testCaseInsensitive() {
        let score = search.score(query: "README", candidate: "readme.md")
        XCTAssertNotNil(score)
    }

    func testSearchReturnsRankedResults() {
        let candidates = ["readme.md", "unread.txt", "spreadsheet.csv", "config.yaml"]
        let results = search.search(query: "read", candidates: candidates)
        XCTAssertFalse(results.isEmpty)
        // "readme.md" should rank first (prefix match)
        XCTAssertEqual(results.first?.path, "readme.md")
    }

    func testSearchRespectsMaxResults() {
        let candidates = (0..<50).map { "file\($0).txt" }
        let results = search.search(query: "file", candidates: candidates, maxResults: 5)
        XCTAssertEqual(results.count, 5)
    }

    func testWordBoundaryBonus() {
        let camelScore = search.score(query: "fs", candidate: "file_service.swift")!
        let middleScore = search.score(query: "fs", candidate: "offset.swift")!
        XCTAssertGreaterThan(camelScore, middleScore)
    }

    func testSearchEmptyCandidatesReturnsEmpty() {
        let results = search.search(query: "readme", candidates: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchNoMatchesReturnsEmpty() {
        let candidates = ["alpha.swift", "beta.swift", "gamma.swift"]
        let results = search.search(query: "zzz", candidates: candidates)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchEmptyQueryReturnsAll() {
        let candidates = ["a.swift", "b.swift", "c.swift"]
        let results = search.search(query: "", candidates: candidates)
        XCTAssertEqual(results.count, candidates.count)
    }

    func testSearchResultsAreSortedByScoreDescending() {
        let candidates = ["readme.md", "src/readme_notes.txt", "z_readme_old.md"]
        let results = search.search(query: "readme", candidates: candidates)
        XCTAssertTrue(results.count >= 2)
        for i in 0..<(results.count - 1) {
            XCTAssertGreaterThanOrEqual(results[i].score, results[i + 1].score)
        }
    }
}
