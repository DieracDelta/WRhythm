//
//  RecentlyPlayedStore.swift
//  WRhythm Watch App
//

import Foundation
import Combine

struct RecentlyPlayedItem: Codable, Identifiable, Sendable {
    let id: UUID
    let song: Song
    let playedAt: Date

    nonisolated init(id: UUID = UUID(), song: Song, playedAt: Date) {
        self.id = id
        self.song = song
        self.playedAt = playedAt
    }
}

struct RecentlyPlayedHistoryPolicy: Sendable {
    nonisolated static let defaultLimit = 200

    nonisolated static func inserting(
        song: Song,
        playedAt: Date,
        into items: [RecentlyPlayedItem],
        limit: Int = defaultLimit
    ) -> [RecentlyPlayedItem] {
        let item = RecentlyPlayedItem(song: song, playedAt: playedAt)
        let trimmed = Array(([item] + items).prefix(max(1, limit)))
        return trimmed
    }
}

@MainActor
final class RecentlyPlayedStore: ObservableObject {
    static let shared = RecentlyPlayedStore()

    @Published private(set) var items: [RecentlyPlayedItem] = []

    private let fileManager: FileManager
    private let fileURL: URL
    private let limit: Int

    convenience init(
        fileManager: FileManager = .default,
        limit: Int = RecentlyPlayedHistoryPolicy.defaultLimit
    ) {
        let baseURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        self.init(
            fileURL: baseURL
                .appendingPathComponent("WRhythm", isDirectory: true)
                .appendingPathComponent("recently_played.json"),
            fileManager: fileManager,
            limit: limit
        )
    }

    init(fileURL: URL, fileManager: FileManager = .default, limit: Int = RecentlyPlayedHistoryPolicy.defaultLimit) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.limit = limit
        load()
    }

    func record(song: Song, playedAt: Date = Date()) {
        items = RecentlyPlayedHistoryPolicy.inserting(song: song, playedAt: playedAt, into: items, limit: limit)
        save()
    }

    func clear() {
        items = []
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("⚠️ Failed to clear recently played history: \(WRhythmLogRedactor.errorSummary(error))")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([RecentlyPlayedItem].self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            items = []
        } catch {
            print("⚠️ Failed to load recently played history: \(WRhythmLogRedactor.errorSummary(error))")
            items = []
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("⚠️ Failed to save recently played history: \(WRhythmLogRedactor.errorSummary(error))")
        }
    }
}
