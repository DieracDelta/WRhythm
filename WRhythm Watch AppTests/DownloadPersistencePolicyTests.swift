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

    @Test func downloadedTracksAreGroupedIntoSearchableAlbumSections() {
        let downloads = [
            makeDownloadedSong(
                id: "b-2",
                title: "Beta Two",
                artist: "Artist B",
                album: "Beta Album",
                downloadedAt: Date(timeIntervalSince1970: 20)
            ),
            makeDownloadedSong(
                id: "a-1",
                title: "Alpha One",
                artist: "Artist A",
                album: "Alpha Album",
                downloadedAt: Date(timeIntervalSince1970: 10)
            ),
            makeDownloadedSong(
                id: "b-1",
                title: "Beta One",
                artist: "Artist B",
                album: "Beta Album",
                downloadedAt: Date(timeIntervalSince1970: 30)
            ),
            makeDownloadedSong(
                id: "unknown",
                title: "Loose Track",
                artist: nil,
                album: nil,
                downloadedAt: Date(timeIntervalSince1970: 40)
            )
        ]

        let sections = DownloadsPresentationPolicy.albumSections(for: downloads, searchText: "")

        #expect(sections.map(\.title) == ["Alpha Album", "Beta Album", "Unknown Album"])
        #expect(sections[0].songs.map(\.songId) == ["a-1"])
        #expect(sections[1].songs.map(\.songId) == ["b-1", "b-2"])
        #expect(sections[2].songs.map(\.songId) == ["unknown"])
    }

    @Test func downloadedAlbumSearchMatchesAlbumArtistAndTrackTitles() {
        let downloads = [
            makeDownloadedSong(id: "one", title: "River", artist: "Yiruma", album: "Piano Songs"),
            makeDownloadedSong(id: "two", title: "Gold Dust", artist: "DJ Fresh", album: "Drum Songs"),
            makeDownloadedSong(id: "three", title: "Intro", artist: "Daft Punk", album: "Discovery")
        ]

        let albumMatch = DownloadsPresentationPolicy.albumSections(for: downloads, searchText: "piano")
        let artistMatch = DownloadsPresentationPolicy.albumSections(for: downloads, searchText: "fresh")
        let titleMatch = DownloadsPresentationPolicy.albumSections(for: downloads, searchText: "intro")

        #expect(albumMatch.map(\.songs).flatMap { $0 }.map(\.songId) == ["one"])
        #expect(artistMatch.map(\.songs).flatMap { $0 }.map(\.songId) == ["two"])
        #expect(titleMatch.map(\.songs).flatMap { $0 }.map(\.songId) == ["three"])
    }

    @Test func downloadedTrackQualityLabelsAreStableAndHumanReadable() {
        #expect(DownloadsPresentationPolicy.qualityLabel(forBitRate: AudioQuality.original.downloadedBitRate) == "Original")
        #expect(DownloadsPresentationPolicy.qualityLabel(forBitRate: 192) == "192 kbps")
        #expect(DownloadsPresentationPolicy.qualityLabel(forBitRate: 320) == "320 kbps")
    }

    @Test func albumQualityChangeTargetsEveryTrackInThatAlbum() {
        let targetAlbum = DownloadedAlbumSection(
            title: "Target Album",
            artist: "Artist",
            coverArt: "cover",
            songs: [
                makeDownloadedSong(id: "one", title: "One", album: "Target Album"),
                makeDownloadedSong(id: "two", title: "Two", album: "Target Album")
            ]
        )

        let targets = DownloadQualityChangePolicy.songIdsForAlbumQualityChange(targetAlbum)

        #expect(targets == ["one", "two"])
    }

    @Test func keepAllAvailableTracksSkipsAlreadyDownloadedSongsAndChunksWork() {
        let songs = (0..<105).map { makeSong(id: "song-\($0)", title: "Song \($0)") }

        let planned = AvailableTrackKeepBatchPolicy.songsToKeep(
            availableSongs: songs,
            downloadedSongIds: ["song-1", "song-50", "song-104"]
        )
        let chunks = AvailableTrackKeepBatchPolicy.chunks(planned, chunkSize: 20)

        #expect(planned.count == 102)
        #expect(planned.contains(where: { $0.id == "song-1" }) == false)
        #expect(chunks.map(\.count) == [20, 20, 20, 20, 20, 2])
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

    private func makeDownloadedSong(
        id: String,
        title: String,
        artist: String? = "Artist",
        album: String? = "Album",
        coverArt: String? = "cover",
        downloadedAt: Date = Date(timeIntervalSince1970: 1_790_000_000),
        downloadedBitRate: Int = 192
    ) -> DownloadedSong {
        DownloadedSong(
            songId: id,
            title: title,
            artist: artist,
            album: album,
            coverArt: coverArt,
            filePath: "\(id).mp3",
            downloadedAt: downloadedAt,
            fileSize: 123,
            downloadedBitRate: downloadedBitRate
        )
    }
}
