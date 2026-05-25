//
//  PlaylistLargeDataTests.swift
//  WRhythm Watch AppTests
//

import Foundation
import Testing
@testable import WRhythm_Watch_App

struct PlaylistLargeDataTests {
    @Test func largePlaylistDisplayItemsPreserveAllRowsAndQueueIndexes() {
        // Given
        let songs = makeSongs(count: 1_500)

        // When
        let items = PlaylistTrackPresentationPolicy.displayItems(songs: songs, queue: songs)

        // Then
        #expect(items.count == 1_500)
        #expect(items.first?.song.id == "song-0")
        #expect(items.first?.queueIndex == 0)
        #expect(items.last?.song.id == "song-1499")
        #expect(items.last?.queueIndex == 1_499)
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func tenThousandTrackPlaylistDisplayItemsRemainStable() {
        // Given
        let songs = makeSongs(count: 10_000)

        // When
        let items = PlaylistTrackPresentationPolicy.displayItems(songs: songs, queue: songs)

        // Then
        #expect(items.count == 10_000)
        #expect(items[0].queueIndex == 0)
        #expect(items[4_999].song.id == "song-4999")
        #expect(items[4_999].queueIndex == 4_999)
        #expect(items[9_999].song.id == "song-9999")
        #expect(items[9_999].queueIndex == 9_999)
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func largeFilteredPlaylistMapsVisibleRowsBackToOriginalQueueIndexes() {
        // Given
        let queue = makeSongs(count: 2_400)
        let visibleSongs = queue.enumerated()
            .filter { index, _ in index.isMultiple(of: 3) }
            .map(\.element)

        // When
        let items = PlaylistTrackPresentationPolicy.displayItems(songs: visibleSongs, queue: queue)

        // Then
        #expect(items.count == 800)
        #expect(items.prefix(5).map(\.queueIndex) == [0, 3, 6, 9, 12])
        #expect(items.last?.queueIndex == 2_397)
    }

    @Test func veryLargeFilteredPlaylistMapsVisibleRowsBackToOriginalQueueIndexes() {
        // Given
        let queue = makeSongs(count: 10_000)
        let visibleSongs = queue.enumerated()
            .filter { index, _ in index % 7 == 3 }
            .map(\.element)

        // When
        let items = PlaylistTrackPresentationPolicy.displayItems(songs: visibleSongs, queue: queue)

        // Then
        #expect(items.count == 1_429)
        #expect(items.prefix(5).map(\.queueIndex) == [3, 10, 17, 24, 31])
        #expect(items.last?.queueIndex == 9_999)
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func duplicateSongIDsInLargePlaylistStillHaveStableRowIDsAndQueueIndexes() {
        // Given
        let queue = makeSongs(count: 1_200, duplicateEvery: 10)

        // When
        let items = PlaylistTrackPresentationPolicy.displayItems(songs: queue, queue: queue)

        // Then
        #expect(items.count == queue.count)
        #expect(Set(items.map(\.id)).count == queue.count)
        #expect(items.map(\.queueIndex) == Array(0..<queue.count))
    }

    @Test func veryLargeFilteredPlaylistWithDuplicateSongIDsStillMapsOccurrencesInOrder() {
        // Given
        let queue = makeSongs(count: 6_000, duplicateEvery: 4)
        let visibleSongs = queue.enumerated()
            .filter { index, _ in index.isMultiple(of: 5) }
            .map(\.element)

        // When
        let items = PlaylistTrackPresentationPolicy.displayItems(songs: visibleSongs, queue: queue)

        // Then
        #expect(items.count == 1_200)
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(items.first?.queueIndex == 0)
        #expect(items[1].queueIndex == 4)
        #expect(items[2].queueIndex == 8)
        #expect(items.last?.queueIndex == 5_992)
    }

    @MainActor
    @Test func largeSubsonicPlaylistPayloadDecodesAllSongs() throws {
        // Given
        let payload = largePlaylistPayload(songCount: 1_250)

        // When
        let response = try JSONDecoder().decode(SubsonicResponse<PlaylistResponse>.self, from: Data(payload.utf8))
        let playlist = try #require(response.subsonicResponse.playlist)

        // Then
        #expect(playlist.songCount == 1_250)
        #expect(playlist.entry?.count == 1_250)
        #expect(playlist.entry?.first?.id == "song-0")
        #expect(playlist.entry?.last?.id == "song-1249")
    }

    private func makeSongs(count: Int, duplicateEvery duplicateStride: Int? = nil) -> [Song] {
        (0..<count).map { index in
            let idIndex = duplicateStride.map { index / $0 } ?? index
            return Song(
                id: "song-\(idIndex)",
                title: "Track \(index)",
                album: "Large Playlist",
                albumId: "album-large",
                artist: "Artist \(index % 17)",
                artistId: "artist-\(index % 17)",
                track: index + 1,
                year: 2026,
                genre: "Test",
                coverArt: "cover-\(index % 8)",
                size: 1_024,
                contentType: "audio/flac",
                suffix: "flac",
                duration: 180,
                bitRate: 900,
                path: "music/song-\(index).flac"
            )
        }
    }

    private func largePlaylistPayload(songCount: Int) -> String {
        let songs = (0..<songCount).map { index in
            """
            {
              "id": "song-\(index)",
              "title": "Track \(index)",
              "album": "Large Playlist",
              "albumId": "album-large",
              "artist": "Artist \(index % 17)",
              "artistId": "artist-\(index % 17)",
              "track": \(index + 1),
              "year": 2026,
              "genre": "Test",
              "coverArt": "cover-\(index % 8)",
              "size": 1024,
              "contentType": "audio/flac",
              "suffix": "flac",
              "duration": 180,
              "bitRate": 900,
              "path": "music/song-\(index).flac"
            }
            """
        }.joined(separator: ",")

        return """
        {
          "subsonic-response": {
            "status": "ok",
            "version": "1.16.1",
            "playlist": {
              "id": "playlist-large",
              "name": "Large Playlist",
              "songCount": \(songCount),
              "duration": \(songCount * 180),
              "created": "2026-05-22T00:00:00Z",
              "changed": "2026-05-22T00:00:00Z",
              "coverArt": "playlist-large",
              "owner": "admin",
              "public": false,
              "entry": [
                \(songs)
              ]
            }
          }
        }
        """
    }
}
