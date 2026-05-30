//
//  DownloadStatePolicies.swift
//  WRhythm Watch App
//

import Foundation

struct DownloadRequestPersistencePolicy: Sendable {
    private struct IncompleteDownloadManifest: Codable, Sendable {
        let version: Int
        let songs: [Song]
    }

    static func encodeIncompleteDownloads(
        queuedSongs: [Song],
        activeSongs: [String: Song]
    ) throws -> Data {
        let songs = orderedUniqueSongs(queuedSongs: queuedSongs, activeSongs: activeSongs)
        let manifest = IncompleteDownloadManifest(version: 2, songs: songs)
        return try JSONEncoder().encode(manifest)
    }

    static func decodeIncompleteDownloads(
        from data: Data,
        songMetadata: [String: Song],
        downloadedSongIds: Set<String>
    ) throws -> [Song] {
        if let manifest = try? JSONDecoder().decode(IncompleteDownloadManifest.self, from: data) {
            return manifest.songs.filter { !downloadedSongIds.contains($0.id) }
        }

        let legacyIds = try JSONDecoder().decode([String].self, from: data)
        return legacyIds.compactMap { songId in
            guard !downloadedSongIds.contains(songId) else { return nil }
            return songMetadata[songId]
        }
    }

    private static func orderedUniqueSongs(queuedSongs: [Song], activeSongs: [String: Song]) -> [Song] {
        var seen = Set<String>()
        var ordered: [Song] = []

        for song in queuedSongs where seen.insert(song.id).inserted {
            ordered.append(song)
        }

        for song in activeSongs.values.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
            where seen.insert(song.id).inserted
        {
            ordered.append(song)
        }

        return ordered
    }
}

enum DownloadRowStatus: Equatable, Sendable {
    case none
    case queued
    case downloading(progress: Double)
    case downloaded
}

struct DownloadStatusPresentationPolicy: Sendable {
    static func status(
        songId: String,
        isDownloaded: Bool,
        activeProgress: Double?,
        queuedSongIds: Set<String>
    ) -> DownloadRowStatus {
        if let activeProgress {
            return .downloading(progress: activeProgress)
        }
        if queuedSongIds.contains(songId) {
            return .queued
        }
        if isDownloaded {
            return .downloaded
        }
        return .none
    }
}

enum DownloadNoticeKind: Equatable, Sendable {
    case song(title: String)
    case album(name: String, queuedCount: Int)
    case playlist(name: String, queuedCount: Int)
}

struct DownloadNoticePresentationPolicy: Sendable {
    static func message(for kind: DownloadNoticeKind) -> String {
        switch kind {
        case .song(let title):
            return "Download \(title) started. See Downloads."
        case .album(let name, let queuedCount):
            return "Downloading \(name): \(trackCountText(queuedCount)). See Downloads."
        case .playlist(let name, let queuedCount):
            return "Downloading \(name): \(trackCountText(queuedCount)). See Downloads."
        }
    }

    private static func trackCountText(_ count: Int) -> String {
        count == 1 ? "1 track" : "\(count) tracks"
    }
}

struct DownloadTaskIdentityPolicy: Sendable {
    static func songId<Task: AnyObject>(
        for task: Task,
        mappedSongId: String?,
        taskDescription: String?
    ) -> String? {
        if let mappedSongId {
            return mappedSongId
        }

        guard let taskDescription,
              !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return taskDescription
    }
}

struct DownloadsPresentationPolicy: Sendable {
    static let unknownAlbumTitle = "Unknown Album"

    @MainActor
    static func sortedVisibleDownloads(
        _ downloads: [DownloadedSong],
        fileExists: @MainActor (DownloadedSong) -> Bool
    ) -> [DownloadedSong] {
        var visibleDownloads: [DownloadedSong] = []
        for download in downloads where fileExists(download) {
            visibleDownloads.append(download)
        }

        return visibleDownloads.sorted { $0.downloadedAt > $1.downloadedAt }
    }

    static func showsEmptyState(visibleDownloadCount: Int) -> Bool {
        visibleDownloadCount == 0
    }

    static func albumSections(for downloads: [DownloadedSong], searchText: String) -> [DownloadedAlbumSection] {
        let filteredDownloads = filteredDownloads(downloads, searchText: searchText)
        let grouped = Dictionary(grouping: filteredDownloads) { download in
            albumSectionKey(for: download)
        }

        return grouped.values.map { downloads in
            let sortedSongs = downloads.sorted {
                let titleComparison = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return $0.downloadedAt > $1.downloadedAt
            }
            let representative = sortedSongs.first
            return DownloadedAlbumSection(
                title: normalizedAlbumTitle(representative?.album),
                artist: representative?.artist,
                coverArt: representative?.coverArt,
                songs: sortedSongs
            )
        }
        .sorted { lhs, rhs in
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return (lhs.artist ?? "").localizedCaseInsensitiveCompare(rhs.artist ?? "") == .orderedAscending
        }
    }

    static func qualityLabel(for download: DownloadedSong) -> String {
        qualityLabel(forBitRate: download.downloadedBitRate)
    }

    static func qualityLabel(forBitRate bitRate: Int) -> String {
        bitRate == AudioQuality.original.downloadedBitRate ? "Original" : "\(bitRate) kbps"
    }

    static func qualitySummary(for downloads: [DownloadedSong]) -> String {
        let labels = Set(downloads.map { qualityLabel(for: $0) })
        guard labels.count == 1, let label = labels.first else {
            return "Mixed"
        }
        return label
    }

    private static func filteredDownloads(_ downloads: [DownloadedSong], searchText: String) -> [DownloadedSong] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return downloads }

        return downloads.filter { download in
            [
                download.title,
                download.artist,
                download.album
            ]
            .compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private static func albumSectionKey(for download: DownloadedSong) -> String {
        "\(normalizedAlbumTitle(download.album))|\(download.artist ?? "")"
    }

    private static func normalizedAlbumTitle(_ title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? unknownAlbumTitle : trimmed
    }
}

struct DownloadedAlbumSection: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String?
    let coverArt: String?
    let songs: [DownloadedSong]

    init(title: String, artist: String?, coverArt: String?, songs: [DownloadedSong]) {
        self.title = title
        self.artist = artist
        self.coverArt = coverArt
        self.songs = songs
        self.id = "\(title)|\(artist ?? "")"
    }

    var totalSize: Int64 {
        songs.reduce(0) { $0 + $1.fileSize }
    }

    var qualitySummary: String {
        DownloadsPresentationPolicy.qualitySummary(for: songs)
    }
}

struct DownloadQualityChangePolicy: Sendable {
    static func songIdsForAlbumQualityChange(_ section: DownloadedAlbumSection) -> [String] {
        section.songs.map(\.songId)
    }
}

struct AvailableTrackKeepBatchPolicy: Sendable {
    static func songsToKeep(availableSongs: [Song], downloadedSongIds: Set<String>) -> [Song] {
        var seen = Set<String>()
        return availableSongs.filter { song in
            guard !downloadedSongIds.contains(song.id) else { return false }
            return seen.insert(song.id).inserted
        }
    }

    static func chunks(_ songs: [Song], chunkSize: Int) -> [[Song]] {
        guard chunkSize > 0 else { return songs.map { [$0] } }
        return stride(from: 0, to: songs.count, by: chunkSize).map { start in
            Array(songs[start..<min(start + chunkSize, songs.count)])
        }
    }
}

struct DownloadedFileCandidate: Equatable, Sendable {
    let fileName: String
    let fileSize: Int64
    let modifiedAt: Date?
}

struct DownloadedFileReconciliationPolicy: Sendable {
    static func reconciledDownloads(
        existingDownloads: [String: DownloadedSong],
        songMetadata: [String: Song],
        files: [DownloadedFileCandidate],
        now: Date
    ) -> [String: DownloadedSong] {
        var reconciled = existingDownloads

        for file in files {
            guard let songId = songId(fromDownloadedFileName: file.fileName),
                  reconciled[songId] == nil,
                  let song = songMetadata[songId]
            else {
                continue
            }

            reconciled[songId] = DownloadedSong(
                songId: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                coverArt: song.coverArt,
                filePath: file.fileName,
                downloadedAt: file.modifiedAt ?? now,
                fileSize: file.fileSize,
                downloadedBitRate: AudioQuality.original.downloadedBitRate
            )
        }

        return reconciled
    }

    static func songId(fromDownloadedFileName fileName: String) -> String? {
        let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let url = URL(fileURLWithPath: trimmedName)
        let songId = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return songId.isEmpty ? nil : songId
    }
}

nonisolated struct CompletedDownloadFileMovePolicy: Sendable {
    static func moveTemporaryDownload(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> Int64 {
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: sourceURL, to: destinationURL)

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        return attributes[.size] as? Int64 ?? 0
    }
}

struct DownloadUserNotice: Identifiable, Equatable, Sendable {
    let id: UUID
    let message: String
    let createdAt: Date

    init(message: String, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.message = message
        self.createdAt = createdAt
    }
}
