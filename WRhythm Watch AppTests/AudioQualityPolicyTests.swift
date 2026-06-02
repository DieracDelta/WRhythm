//
//  AudioQualityPolicyTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing
@testable import WRhythm_Watch_App

struct AudioQualityPolicyTests {
    @Test func originalDownloadsDoNotRequestTranscoding() {
        #expect(AudioQuality.original.streamFormat == nil)
        #expect(AudioQuality.original.maxBitRate == nil)
        #expect(AudioQuality.original.downloadedBitRate == 0)
        #expect(AudioQuality.original.shortDescription == "Original")
    }

    @Test func lossyDownloadsRequestMP3TranscodingAtSelectedBitrate() {
        #expect(AudioQuality.low.streamFormat == "mp3")
        #expect(AudioQuality.low.maxBitRate == 64)
        #expect(AudioQuality.medium.streamFormat == "mp3")
        #expect(AudioQuality.medium.maxBitRate == 128)
        #expect(AudioQuality.high.streamFormat == "mp3")
        #expect(AudioQuality.high.maxBitRate == 192)
        #expect(AudioQuality.max.streamFormat == "mp3")
        #expect(AudioQuality.max.maxBitRate == 320)
    }

    @Test func absentSavedDownloadQualityStillDefaultsToMedium() {
        #expect(AudioQuality.savedQuality(from: nil) == .medium)
    }

    @Test func storedZeroDownloadQualityRestoresOriginal() {
        #expect(AudioQuality.savedQuality(from: 0) == .original)
    }

    @Test func originalDownloadsUseSongSuffixForLocalFilename() {
        let song = makeSong(id: "flac-song", suffix: "flac")

        #expect(AudioQuality.original.localFileExtension(for: song) == "flac")
        #expect(AudioQuality.medium.localFileExtension(for: song) == "mp3")
    }

    @Test func originalDownloadsFallBackToGenericExtensionForUnsafeSuffix() {
        let song = makeSong(id: "unsafe-song", suffix: "../flac")

        #expect(AudioQuality.original.localFileExtension(for: song) == "audio")
    }

    @Test func prebufferQualityLabelsUseDownloadedBitRateMetadata() {
        #expect(PrebufferQualityPresentationPolicy.downloadedQualityLabel(downloadedBitRate: 0) == "Original")
        #expect(PrebufferQualityPresentationPolicy.downloadedQualityLabel(downloadedBitRate: 192) == "192 kbps")
    }

    @Test func availableTrackKeepPolicyDerivesDurableDownloadMetadata() {
        #expect(AvailableTrackKeepPolicy.destinationFileName(songId: "song-1", sourceExtension: "mp3") == "song-1.mp3")
        #expect(AvailableTrackKeepPolicy.destinationFileName(songId: "song-1", sourceExtension: "") == "song-1.audio")
        #expect(AvailableTrackKeepPolicy.destinationFileName(songId: "song-1", sourceExtension: "../flac") == "song-1.audio")
        #expect(AvailableTrackKeepPolicy.downloadedBitRate(fromQualityLabel: "Original") == 0)
        #expect(AvailableTrackKeepPolicy.downloadedBitRate(fromQualityLabel: "192 kbps") == 192)
        #expect(AvailableTrackKeepPolicy.downloadedBitRate(fromQualityLabel: "Downloaded") == 0)
    }

    @Test func prebufferQualityLabelsReflectPlaybackTranscoding() {
        #expect(PrebufferQualityPresentationPolicy.streamingQualityLabel(
            streamingQuality: .original,
            transcodesToMP3: false
        ) == "Original")
        #expect(PrebufferQualityPresentationPolicy.streamingQualityLabel(
            streamingQuality: .high,
            transcodesToMP3: true
        ) == "192 kbps")
        #expect(PrebufferQualityPresentationPolicy.streamingQualityLabel(
            streamingQuality: .original,
            transcodesToMP3: true
        ) == "MP3 fallback 320 kbps")
    }

    @Test func playbackQualitySummaryNamesTransportAndQuality() {
        #expect(PlaybackQualityPresentationPolicy.statusText(
            source: .streaming,
            qualityLabel: "192 kbps"
        ) == "Streaming: 192 kbps")
        #expect(PlaybackQualityPresentationPolicy.statusText(
            source: .local,
            qualityLabel: "Original"
        ) == "Local: Original")
        #expect(PlaybackQualityPresentationPolicy.statusText(
            source: .streaming,
            qualityLabel: " "
        ) == "Streaming: Unknown")
    }

    @Test func errorCopyTextIncludesUserAndTechnicalDetails() {
        let text = WRhythmErrorCopyPolicy.copyText(
            title: "Playback retry limit reached",
            message: "Could not play track.",
            technicalDetails: "AVFoundation code -1003",
            recoverySuggestion: "Try a lower streaming quality."
        )

        #expect(text.contains("Playback retry limit reached"))
        #expect(text.contains("Could not play track."))
        #expect(text.contains("Details:\nAVFoundation code -1003"))
        #expect(text.contains("Recovery:\nTry a lower streaming quality."))
    }

    @Test func availablePrebufferPresentationIncludesPreparedTracksOutsideQueue() {
        let queuedReady = makeSong(id: "queued-ready", title: "Queued Ready")
        let queuedMissing = makeSong(id: "queued-missing", title: "Queued Missing")
        let lingeringB = makeSong(id: "lingering-b", title: "Zulu")
        let lingeringA = makeSong(id: "lingering-a", title: "Alpha")

        let songs = PrebufferAvailabilityPresentationPolicy.orderedAvailableSongs(
            queuedSongs: [queuedReady, queuedMissing],
            preparedSongs: [lingeringB, queuedReady, lingeringA]
        )

        #expect(songs.map(\.id) == ["queued-ready", "lingering-a", "lingering-b"])
    }

    @Test func availablePrebufferPresentationDeduplicatesRepeatedPreparedTracks() {
        let first = makeSong(id: "same", title: "Same")
        let second = makeSong(id: "same", title: "Same Again")

        let songs = PrebufferAvailabilityPresentationPolicy.orderedAvailableSongs(
            queuedSongs: [],
            preparedSongs: [first, second]
        )

        #expect(songs.map(\.id) == ["same"])
    }

    @Test func prebufferManifestRestoresOnlyExistingFilesAndKeepsNewestRecordPerKey() {
        let oldRecord = PersistedPrebufferRecord(
            key: "same|q192",
            filename: "same-old.mp3",
            song: makeSong(id: "same", title: "Old Same"),
            qualityLabel: "192 kbps",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newRecord = PersistedPrebufferRecord(
            key: "same|q192",
            filename: "same-new.mp3",
            song: makeSong(id: "same", title: "New Same"),
            qualityLabel: "192 kbps",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let missingRecord = PersistedPrebufferRecord(
            key: "missing|q192",
            filename: "missing.mp3",
            song: makeSong(id: "missing", title: "Missing"),
            qualityLabel: "192 kbps",
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let records = PrebufferManifestPolicy.restorableRecords(
            records: [oldRecord, newRecord, missingRecord],
            existingFilenames: ["same-old.mp3", "same-new.mp3"]
        )

        #expect(records.map(\.filename) == ["same-new.mp3"])
    }

    @Test func storedAlbumArtworkPolicyBuildsFilesystemSafeNames() {
        let fileName = StoredAlbumArtworkPolicy.fileName(for: "artist/album+cover==")

        #expect(fileName.hasSuffix(".img"))
        #expect(!fileName.contains("/"))
        #expect(!fileName.contains("+"))
        #expect(!fileName.contains("="))
    }

    private func makeSong(id: String, suffix: String?) -> Song {
        makeSong(id: id, title: "Track", suffix: suffix)
    }

    private func makeSong(id: String, title: String, suffix: String? = nil) -> Song {
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
            coverArt: nil,
            size: nil,
            contentType: suffix.map { "audio/\($0)" },
            suffix: suffix,
            duration: 180,
            bitRate: nil,
            path: nil
        )
    }
}
