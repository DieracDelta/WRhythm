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

    private func makeSong(id: String, suffix: String?) -> Song {
        Song(
            id: id,
            title: "Track",
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
