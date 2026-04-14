//
//  BundlingDatabase.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 4/12/26.
//

import Foundation

/// Loads NCCI PTP edit pairs from bundling_pairs.json and provides fast lookup
/// for unbundling detection. Each pair has a Column 1 (payable) code, Column 2
/// (denied) code, modifier indicator, and rationale category.
struct BundlingDatabase {

    struct PTPPair {
        let col1: String   // Payable code
        let col2: String   // Denied code (component)
        let modifier: Int  // 0 = never together, 1 = allowed with modifier
        let rationale: Int // 1-7 category
    }

    /// Lookup: col1 code -> set of col2 codes that are bundled into it
    private var col1Lookup: [String: [PTPPair]] = [:]
    /// Reverse lookup: col2 code -> set of col1 codes it's bundled into
    private var col2Lookup: [String: [PTPPair]] = [:]

    private(set) var pairCount: Int = 0

    static let shared = BundlingDatabase()

    private init() {
        load()
    }

    private mutating func load() {
        guard let url = Bundle.main.url(forResource: "bundling_pairs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }

        struct RawPair: Decodable {
            let col1: String
            let col2: String
            let modifier: Int
            let rationale: Int
        }

        guard let rawPairs = try? JSONDecoder().decode([RawPair].self, from: data) else {
            return
        }

        var c1: [String: [PTPPair]] = [:]
        var c2: [String: [PTPPair]] = [:]

        for raw in rawPairs {
            let pair = PTPPair(
                col1: raw.col1,
                col2: raw.col2,
                modifier: raw.modifier,
                rationale: raw.rationale
            )
            c1[raw.col1, default: []].append(pair)
            c2[raw.col2, default: []].append(pair)
        }

        col1Lookup = c1
        col2Lookup = c2
        pairCount = rawPairs.count
    }

    /// Check if two codes form a bundling pair.
    /// Returns the PTP pair if col1 includes col2 (or vice versa), nil otherwise.
    func findBundlingPair(code1: String, code2: String) -> PTPPair? {
        // Check code1 as Column 1 (comprehensive), code2 as Column 2 (component)
        if let pairs = col1Lookup[code1] {
            if let match = pairs.first(where: { $0.col2 == code2 }) {
                return match
            }
        }
        // Check reverse: code2 as Column 1, code1 as Column 2
        if let pairs = col1Lookup[code2] {
            if let match = pairs.first(where: { $0.col2 == code1 }) {
                return match
            }
        }
        return nil
    }

    /// Get all component codes that are bundled into the given comprehensive code.
    func componentsOf(code: String) -> [PTPPair] {
        col1Lookup[code] ?? []
    }

    /// Get all comprehensive codes that the given component code is bundled into.
    func comprehensiveCodesFor(component: String) -> [PTPPair] {
        col2Lookup[component] ?? []
    }

    /// Check if two codes should NEVER be billed together (modifier = 0).
    func isNeverTogether(code1: String, code2: String) -> Bool {
        guard let pair = findBundlingPair(code1: code1, code2: code2) else {
            return false
        }
        return pair.modifier == 0
    }
}
