//
//  RecentlyPlayedHistoryPolicyTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing
@testable import WRhythm_Watch_App

struct RecentlyPlayedHistoryPolicyTests {
    @Test func insertedSongAppearsFirst() {
        let older = song(id: "older")
        let newer = song(id: "newer")
        let start = Date(timeIntervalSince1970: 1_000)
        let existing = [
            RecentlyPlayedItem(song: older, playedAt: start)
        ]

        let result = RecentlyPlayedHistoryPolicy.inserting(
            song: newer,
            playedAt: start.addingTimeInterval(60),
            into: existing,
            limit: 10
        )

        #expect(result.map(\.song.id) == ["newer", "older"])
    }

    @Test func historyIsTrimmedToLimit() {
        let start = Date(timeIntervalSince1970: 1_000)
        let existing = (0..<5).map { index in
            RecentlyPlayedItem(song: song(id: "old-\(index)"), playedAt: start.addingTimeInterval(Double(index)))
        }

        let result = RecentlyPlayedHistoryPolicy.inserting(
            song: song(id: "new"),
            playedAt: start.addingTimeInterval(99),
            into: existing,
            limit: 3
        )

        #expect(result.map(\.song.id) == ["new", "old-0", "old-1"])
    }

    @Test func repeatedPlaysAreKeptAsSeparateHistoryEntries() {
        let playedSong = song(id: "repeat")
        let start = Date(timeIntervalSince1970: 1_000)
        let first = RecentlyPlayedHistoryPolicy.inserting(
            song: playedSong,
            playedAt: start,
            into: [],
            limit: 10
        )
        let second = RecentlyPlayedHistoryPolicy.inserting(
            song: playedSong,
            playedAt: start.addingTimeInterval(60),
            into: first,
            limit: 10
        )

        #expect(second.count == 2)
        #expect(second[0].song.id == "repeat")
        #expect(second[1].song.id == "repeat")
        #expect(second[0].id != second[1].id)
    }

    private func song(id: String) -> Song {
        Song(
            id: id,
            title: "Song \(id)",
            album: "Album",
            albumId: "album-\(id)",
            artist: "Artist",
            artistId: "artist-\(id)",
            track: 1,
            year: 2026,
            genre: "Test",
            coverArt: nil,
            size: nil,
            contentType: "audio/mpeg",
            suffix: "mp3",
            duration: 180,
            bitRate: 192,
            path: nil
        )
    }
}
