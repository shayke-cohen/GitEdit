import Foundation

/// Fuzzy file search for Quick Open (Cmd+P).
public struct FuzzySearch: Sendable {

    public init() {}

    /// Score a candidate filename against a query.
    /// Higher score = better match. Returns nil if no match.
    public func score(query: String, candidate: String) -> Int? {
        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate.lowercased())

        guard !queryChars.isEmpty else { return 0 }

        var score = 0
        var queryIndex = 0
        var lastMatchIndex = -1
        var consecutiveBonus = 0

        for (i, char) in candidateChars.enumerated() {
            guard queryIndex < queryChars.count else { break }

            if char == queryChars[queryIndex] {
                score += 1

                // Bonus for consecutive matches
                if lastMatchIndex == i - 1 {
                    consecutiveBonus += 2
                    score += consecutiveBonus
                } else {
                    consecutiveBonus = 0
                }

                // Bonus for matching at word boundaries (after /, -, _, .)
                if i == 0 || "/\\-_.".contains(candidateChars[i - 1]) {
                    score += 5
                }

                // Bonus for matching at start
                if i == 0 {
                    score += 3
                }

                lastMatchIndex = i
                queryIndex += 1
            }
        }

        // All query characters must be found
        guard queryIndex == queryChars.count else { return nil }

        // Penalty for longer candidates (prefer shorter matches)
        score -= candidateChars.count / 10

        return score
    }

    /// Search a list of file paths and return ranked results.
    public func search(query: String, candidates: [String], maxResults: Int = 20) -> [SearchResult] {
        candidates.compactMap { candidate in
            guard let matchScore = score(query: query, candidate: candidate) else { return nil }
            return SearchResult(path: candidate, score: matchScore)
        }
        .sorted { $0.score > $1.score }
        .prefix(maxResults)
        .map { $0 }
    }
}

public struct SearchResult: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let score: Int

    public init(path: String, score: Int) {
        self.path = path
        self.score = score
    }
}
