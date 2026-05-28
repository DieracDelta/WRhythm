//
//  SortOptionsPolicyTests.swift
//  WRhythm Watch AppTests
//

import Testing
@testable import WRhythm_Watch_App

struct SortOptionsPolicyTests {
    @Test func albumSortsByTitleArtistNewestAndTrackCount() {
        let albums = [
            album(id: "a", name: "Zeta", artist: "Beta", songCount: 4, created: "2024-01-01T00:00:00", year: 2024),
            album(id: "b", name: "Alpha", artist: "Delta", songCount: 12, created: "2023-01-01T00:00:00", year: 2023),
            album(id: "c", name: "Middle", artist: "Alpha", songCount: 8, created: "2025-01-01T00:00:00", year: 2025),
        ]

        #expect(AlbumSortOption.titleAscending.sorted(albums).map(\.id) == ["b", "c", "a"])
        #expect(AlbumSortOption.artistAscending.sorted(albums).map(\.id) == ["c", "a", "b"])
        #expect(AlbumSortOption.newest.sorted(albums).map(\.id) == ["c", "a", "b"])
        #expect(AlbumSortOption.mostTracks.sorted(albums).map(\.id) == ["b", "c", "a"])
    }

    @Test func artistSortsByNameAndAlbumCount() {
        let artists = [
            Artist(id: "a", name: "Zed", albumCount: 2, coverArt: nil),
            Artist(id: "b", name: "Ann", albumCount: 8, coverArt: nil),
            Artist(id: "c", name: "Mia", albumCount: 1, coverArt: nil),
        ]

        #expect(ArtistSortOption.nameAscending.sorted(artists).map(\.id) == ["b", "c", "a"])
        #expect(ArtistSortOption.mostAlbums.sorted(artists).map(\.id) == ["b", "a", "c"])
        #expect(ArtistSortOption.fewestAlbums.sorted(artists).map(\.id) == ["c", "a", "b"])
    }

    @Test func playlistSortsByNameChangedAndTrackCount() {
        let playlists = [
            playlist(id: "a", name: "Zed", songCount: 12, changed: "2024-01-01T00:00:00"),
            playlist(id: "b", name: "Ann", songCount: 3, changed: "2026-01-01T00:00:00"),
            playlist(id: "c", name: "Mia", songCount: 40, changed: "2025-01-01T00:00:00"),
        ]

        #expect(PlaylistSortOption.nameAscending.sorted(playlists).map(\.id) == ["b", "c", "a"])
        #expect(PlaylistSortOption.recentlyChanged.sorted(playlists).map(\.id) == ["b", "c", "a"])
        #expect(PlaylistSortOption.mostTracks.sorted(playlists).map(\.id) == ["c", "a", "b"])
        #expect(PlaylistSortOption.fewestTracks.sorted(playlists).map(\.id) == ["b", "a", "c"])
    }

    @Test func songSortsByTrackTitleArtistAlbumAndDuration() {
        let songs = [
            song(id: "a", title: "Zed", album: "Two", artist: "Beta", track: 2, duration: 100),
            song(id: "b", title: "Ann", album: "One", artist: "Delta", track: 1, duration: 400),
            song(id: "c", title: "Mia", album: "Three", artist: "Alpha", track: 3, duration: 50),
        ]

        #expect(SongSortOption.original.sorted(songs).map(\.id) == ["a", "b", "c"])
        #expect(SongSortOption.trackNumber.sorted(songs).map(\.id) == ["b", "a", "c"])
        #expect(SongSortOption.titleAscending.sorted(songs).map(\.id) == ["b", "c", "a"])
        #expect(SongSortOption.artistAscending.sorted(songs).map(\.id) == ["c", "a", "b"])
        #expect(SongSortOption.albumAscending.sorted(songs).map(\.id) == ["b", "c", "a"])
        #expect(SongSortOption.longest.sorted(songs).map(\.id) == ["b", "a", "c"])
        #expect(SongSortOption.shortest.sorted(songs).map(\.id) == ["c", "a", "b"])
    }

    private func album(
        id: String,
        name: String,
        artist: String,
        songCount: Int,
        created: String,
        year: Int
    ) -> AlbumSummary {
        AlbumSummary(
            id: id,
            name: name,
            artist: artist,
            artistId: nil,
            coverArt: nil,
            songCount: songCount,
            duration: 0,
            created: created,
            year: year
        )
    }

    private func playlist(id: String, name: String, songCount: Int, changed: String) -> PlaylistSummary {
        PlaylistSummary(
            id: id,
            name: name,
            songCount: songCount,
            duration: 0,
            created: "2024-01-01T00:00:00",
            changed: changed,
            coverArt: nil,
            owner: nil,
            public: nil
        )
    }

    private func song(
        id: String,
        title: String,
        album: String,
        artist: String,
        track: Int,
        duration: Int
    ) -> Song {
        Song(
            id: id,
            title: title,
            album: album,
            albumId: nil,
            artist: artist,
            artistId: nil,
            track: track,
            year: nil,
            genre: nil,
            coverArt: nil,
            size: nil,
            contentType: nil,
            suffix: nil,
            duration: duration,
            bitRate: nil,
            path: nil
        )
    }
}
