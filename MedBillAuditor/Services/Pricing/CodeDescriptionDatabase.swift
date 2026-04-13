//
//  CodeDescriptionDatabase.swift
//  MedBillAuditor
//
//  Created by Derek Davis on 4/12/26.
//

import Foundation

/// Provides plain-English descriptions for CPT/HCPCS codes.
/// Descriptions are our own (not AMA-copyrighted).
struct CodeDescriptionDatabase {

    struct CodeEntry: Decodable {
        let code: String
        let description: String
        let category: String
    }

    private var entries: [String: CodeEntry] = [:]

    static let shared = CodeDescriptionDatabase()

    private init() {
        load()
    }

    private mutating func load() {
        guard let url = Bundle.main.url(forResource: "code_descriptions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([CodeEntry].self, from: data) else {
            return
        }
        for entry in list {
            entries[entry.code] = entry
        }
    }

    func description(for code: String) -> String? {
        entries[code]?.description
    }

    func category(for code: String) -> String? {
        entries[code]?.category
    }

    func entry(for code: String) -> CodeEntry? {
        entries[code]
    }

    var count: Int { entries.count }
}
