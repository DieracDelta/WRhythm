//
//  DownloadPersistencePolicyTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing
@testable import WRhythm_Watch_App

@MainActor
struct DownloadPersistencePolicyTests {
    @Test func incompleteDownloadsPersistFullQueuedSongsWithoutExternalMetadata() throws {
        let queued = makeSong(id: "queued", title: "Queued Track")

        let data = try DownloadRequestPersistencePolicy.encodeIncompleteDownloads(
            queuedSongs: [queued],
            activeSongs: [:]
        )
        let restored = try DownloadRequestPersistencePolicy.decodeIncompleteDownloads(
            from: data,
            songMetadata: [:],
            downloadedSongIds: []
        )

        #expect(restored.map(\.id) == ["queued"])
        #expect(restored.first?.title == "Queued Track")
    }

    @Test func incompleteDownloadsPersistFullActiveSongsForRestartResume() throws {
        let active = makeSong(id: "active", title: "Active Track")

        let data = try DownloadRequestPersistencePolicy.encodeIncompleteDownloads(
            queuedSongs: [],
            activeSongs: ["active": active]
        )
        let restored = try DownloadRequestPersistencePolicy.decodeIncompleteDownloads(
            from: data,
            songMetadata: [:],
            downloadedSongIds: []
        )

        #expect(restored.map(\.id) == ["active"])
    }

    @Test func incompleteDownloadsStillReadLegacyIdOnlyFilesWhenMetadataExists() throws {
        let legacySong = makeSong(id: "legacy", title: "Legacy Track")
        let legacyData = try JSONEncoder().encode(["legacy"])

        let restored = try DownloadRequestPersistencePolicy.decodeIncompleteDownloads(
            from: legacyData,
            songMetadata: ["legacy": legacySong],
            downloadedSongIds: []
        )

        #expect(restored.map(\.title) == ["Legacy Track"])
    }

    @Test func incompleteDownloadsDoNotRestoreAlreadyDownloadedSongs() throws {
        let queued = makeSong(id: "queued", title: "Queued Track")
        let completed = makeSong(id: "completed", title: "Completed Track")

        let data = try DownloadRequestPersistencePolicy.encodeIncompleteDownloads(
            queuedSongs: [queued, completed],
            activeSongs: [:]
        )
        let restored = try DownloadRequestPersistencePolicy.decodeIncompleteDownloads(
            from: data,
            songMetadata: [:],
            downloadedSongIds: ["completed"]
        )

        #expect(restored.map(\.id) == ["queued"])
    }

    @Test func downloadStatusPresentationPrioritizesActiveThenCompleted() {
        #expect(DownloadStatusPresentationPolicy.status(
            songId: "song",
            isDownloaded: true,
            activeProgress: 0.42,
            queuedSongIds: []
        ) == .downloading(progress: 0.42))

        #expect(DownloadStatusPresentationPolicy.status(
            songId: "song",
            isDownloaded: true,
            activeProgress: nil,
            queuedSongIds: []
        ) == .downloaded)

        #expect(DownloadStatusPresentationPolicy.status(
            songId: "song",
            isDownloaded: false,
            activeProgress: nil,
            queuedSongIds: ["song"]
        ) == .queued)
    }

    @Test func downloadNoticeTitlesAreTerseAndActionable() {
        #expect(DownloadNoticePresentationPolicy.message(for: .song(title: "Track")) == "Download Track started. See Downloads.")
        #expect(DownloadNoticePresentationPolicy.message(for: .album(name: "Album", queuedCount: 12)) == "Downloading Album: 12 tracks. See Downloads.")
        #expect(DownloadNoticePresentationPolicy.message(for: .playlist(name: "Playlist", queuedCount: 3)) == "Downloading Playlist: 3 tracks. See Downloads.")
    }

    @Test func completedBackgroundTaskCanResolveSongIdFromTaskDescriptionWhenObjectMappingIsGone() {
        let task = NSObject()

        let resolved = DownloadTaskIdentityPolicy.songId(
            for: task,
            mappedSongId: nil,
            taskDescription: "song-from-background-session"
        )

        #expect(resolved == "song-from-background-session")
    }

    @Test func completedBackgroundTaskPrefersLiveMappingWhenPresent() {
        let task = NSObject()

        let resolved = DownloadTaskIdentityPolicy.songId(
            for: task,
            mappedSongId: "live-mapping",
            taskDescription: "stale-description"
        )

        #expect(resolved == "live-mapping")
    }

    @Test func downloadsViewShowsCompletedDownloadsOnlyWhenTheirFilesStillExist() {
        let oldDownload = makeDownloadedSong(id: "old", title: "Old", downloadedAt: Date(timeIntervalSince1970: 10))
        let newestDownload = makeDownloadedSong(id: "new", title: "New", downloadedAt: Date(timeIntervalSince1970: 20))
        let missingFileDownload = makeDownloadedSong(id: "missing", title: "Missing", downloadedAt: Date(timeIntervalSince1970: 30))

        let visible = DownloadsPresentationPolicy.sortedVisibleDownloads(
            [oldDownload, missingFileDownload, newestDownload],
            fileExists: { $0.songId != "missing" }
        )

        #expect(visible.map(\.songId) == ["new", "old"])
        #expect(DownloadsPresentationPolicy.showsEmptyState(visibleDownloadCount: visible.count) == false)
        #expect(DownloadsPresentationPolicy.showsEmptyState(visibleDownloadCount: 0))
    }

    @Test func downloadedMetadataWithoutQualityStillLoadsAsOriginalQuality() throws {
        let json = """
        {
          "song-1": {
            "songId": "song-1",
            "title": "Downloaded Track",
            "artist": "Artist",
            "album": "Album",
            "coverArt": "cover",
            "filePath": "song-1.mp3",
            "downloadedAt": "2026-05-30T14:00:00Z",
            "fileSize": 12345
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode([String: DownloadedSong].self, from: Data(json.utf8))

        let song = try #require(decoded["song-1"])
        #expect(song.downloadedBitRate == AudioQuality.original.downloadedBitRate)
        #expect(song.title == "Downloaded Track")
    }

    @Test func completedFilesOnDiskBecomeVisibleDownloadsEvenWhenDownloadMetadataIsMissing() {
        let song = makeSong(id: "disk-only-song", title: "Disk Only Track")
        let modifiedAt = Date(timeIntervalSince1970: 1_790_000_000)

        let reconciled = DownloadedFileReconciliationPolicy.reconciledDownloads(
            existingDownloads: [:],
            songMetadata: [song.id: song],
            files: [
                DownloadedFileCandidate(
                    fileName: "disk-only-song.mp3",
                    fileSize: 55_000,
                    modifiedAt: modifiedAt
                )
            ],
            now: Date(timeIntervalSince1970: 1_790_000_100)
        )

        let downloaded = reconciled[song.id]
        #expect(downloaded?.title == "Disk Only Track")
        #expect(downloaded?.filePath == "disk-only-song.mp3")
        #expect(downloaded?.fileSize == 55_000)
        #expect(downloaded?.downloadedAt == modifiedAt)
        #expect(DownloadsPresentationPolicy.showsEmptyState(visibleDownloadCount: reconciled.count) == false)
    }

    @Test func completedDownloadTempFileIsMovedBeforeDelegateLocationExpires() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wrhythm-download-move-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = tempDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = sourceDirectory.appendingPathComponent("CFNetworkDownload_test.tmp")
        let destinationURL = destinationDirectory.appendingPathComponent("song.flac")
        let payload = Data("downloaded audio bytes".utf8)
        try payload.write(to: sourceURL)

        let fileSize = try CompletedDownloadFileMovePolicy.moveTemporaryDownload(
            from: sourceURL,
            to: destinationURL
        )

        #expect(fileSize == Int64(payload.count))
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
    }

    private func makeSong(id: String, title: String) -> Song {
        Song(
            id: id,
            title: title,
            album: "Album",
            albumId: "album",
            artist: "Artist",
            artistId: "artist",
            track: 1,
            year: 2026,
            genre: "Test",
            coverArt: "cover",
            size: 123,
            contentType: "audio/mpeg",
            suffix: "mp3",
            duration: 180,
            bitRate: 192,
            path: nil
        )
    }

    private func makeDownloadedSong(id: String, title: String, downloadedAt: Date) -> DownloadedSong {
        DownloadedSong(
            songId: id,
            title: title,
            artist: "Artist",
            album: "Album",
            coverArt: "cover",
            filePath: "\(id).mp3",
            downloadedAt: downloadedAt,
            fileSize: 123,
            downloadedBitRate: 192
        )
    }
}
