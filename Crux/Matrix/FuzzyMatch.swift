//
//  FuzzyMatch.swift
//  Crux
//

import Foundation

/// for searching and stuff
enum FuzzyMatch {
    /// Nil when `query` isn't a subsequence of `candidate`.
    static func score(_ query: String, in candidate: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let needle = Array(query.lowercased())
        let haystack = Array(candidate.lowercased())

        var needleIndex = 0
        var score = 0
        var previousMatched = false
        var atWordStart = true

        for char in haystack {
            if needleIndex < needle.count, char == needle[needleIndex] {
                score += previousMatched ? 3 : 1
                if atWordStart { score += 2 }
                previousMatched = true
                needleIndex += 1
            } else {
                previousMatched = false
            }
            atWordStart = Self.wordBreaks.contains(char)
        }

        return needleIndex == needle.count ? score : nil
    }

    private static let wordBreaks: Set<Character> = [" ", "-", "_", ":", "#", "!", "."]
}
