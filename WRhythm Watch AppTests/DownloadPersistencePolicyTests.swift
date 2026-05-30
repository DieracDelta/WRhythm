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
