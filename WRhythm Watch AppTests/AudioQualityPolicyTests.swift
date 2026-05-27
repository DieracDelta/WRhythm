//
//  AudioQualityPolicyTests.swift
//  WRhythm Watch AppTests
//

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
        ) == "320 kbps")
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
