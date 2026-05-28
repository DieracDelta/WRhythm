//
//  SearchResultDiskCache.swift
//  WRhythm Watch App
//

import Foundation

struct CachedSearchResult: Codable, Sendable {
    let query: String
    let cachedAt: Date
    let result: SearchResult
}

enum SearchResultDiskCache {
    private static let fileName = "last_search_result.json"

    static func loadLastSearch() -> CachedSearchResult? {
        do {
            let data = try Data(contentsOf: cacheURL())
            return try JSONDecoder().decode(CachedSearchResult.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            print("⚠️ Failed to load cached search results: \(WRhythmLogRedactor.errorSummary(error))")
            return nil
        }
    }

    static func save(query: String, result: SearchResult) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        do {
            let cached = CachedSearchResult(query: trimmedQuery, cachedAt: Date(), result: result)
            let data = try JSONEncoder().encode(cached)
            let url = try cacheURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("⚠️ Failed to save cached search results: \(WRhythmLogRedactor.errorSummary(error))")
        }
    }

    static func clear() {
        do {
            let url = try cacheURL()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("⚠️ Failed to clear cached search results: \(WRhythmLogRedactor.errorSummary(error))")
        }
    }

    private static func cacheURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL.appendingPathComponent("WRhythm", isDirectory: true).appendingPathComponent(fileName)
    }
}
