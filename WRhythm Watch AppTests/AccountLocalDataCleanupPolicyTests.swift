//
//  AccountLocalDataCleanupPolicyTests.swift
//  WRhythm Watch AppTests
//

import Testing
@testable import WRhythm_Watch_App

@Suite("Account local data cleanup")
struct AccountLocalDataCleanupPolicyTests {
    @Test func accountChangeClearsOnlyWhenServerOrUserChanges() {
        // Given
        let existingURL = "https://navidrome.example.com/"
        let existingUsername = "admin"

        // Then
        #expect(AccountIdentityPolicy.shouldClearLocalData(
            existingBaseURL: existingURL,
            existingUsername: existingUsername,
            incomingBaseURL: "https://navidrome.example.com",
            incomingUsername: "admin"
        ) == false)
        #expect(AccountIdentityPolicy.shouldClearLocalData(
            existingBaseURL: existingURL,
            existingUsername: existingUsername,
            incomingBaseURL: "https://audiomuse.example.com",
            incomingUsername: "admin"
        ))
        #expect(AccountIdentityPolicy.shouldClearLocalData(
            existingBaseURL: existingURL,
            existingUsername: existingUsername,
            incomingBaseURL: "https://navidrome.example.com",
            incomingUsername: "different-user"
        ))
    }

    @Test func cleanupPlanIncludesEveryAccountBoundCache() {
        // Given
        let domains = AccountLocalDataCleanupPlan.accountBoundDomains

        // Then
        #expect(domains.contains(.audioPlayback))
        #expect(domains.contains(.prebufferCache))
        #expect(domains.contains(.downloadsAndMetadata))
        #expect(domains.contains(.libraryData))
        #expect(domains.contains(.recentlyPlayed))
        #expect(domains.contains(.searchResults))
        #expect(domains.contains(.sharedPlaybackSession))
        #expect(domains.contains(.imageCache))
        #expect(domains.contains(.serverCapabilityCache))
    }

    @MainActor
    @Test func libraryDataManagerClearsVisibleAccountData() {
        // Given
        let manager = LibraryDataManager()
        manager.artists = [Artist(id: "artist", name: "Old Artist", albumCount: 1, coverArt: nil)]
        manager.playlists = [PlaylistSummary(
            id: "playlist",
            name: "Old Playlist",
            songCount: 1,
            duration: 60,
            created: "2026-01-01T00:00:00Z",
            changed: "2026-01-01T00:00:00Z",
            coverArt: nil,
            owner: nil,
            public: nil
        )]
        manager.albums = [AlbumSummary(
            id: "album",
            name: "Old Album",
            artist: "Old Artist",
            artistId: "artist",
            coverArt: nil,
            songCount: 1,
            duration: 60,
            created: "2026-01-01T00:00:00Z",
            year: 2026
        )]
        manager.starred = StarredContent(artist: [], album: [], song: [song(id: "old")])
        manager.isLoadingArtists = true
        manager.isLoadingPlaylists = true
        manager.isLoadingAlbums = true
        manager.isLoadingStarred = true
        manager.artistsErrorMessage = "old"
        manager.playlistsErrorMessage = "old"
        manager.albumsErrorMessage = "old"
        manager.starredErrorMessage = "old"
        manager.albumOffset = 100
        manager.hasMoreAlbums = false
        manager.hasEarlierAlbums = true
        manager.albumListType = "alphabeticalByName"

        // When
        manager.clearAccountBoundData()

        // Then
        #expect(manager.artists.isEmpty)
        #expect(manager.playlists.isEmpty)
        #expect(manager.albums.isEmpty)
        #expect(manager.starred == nil)
        #expect(manager.isLoadingArtists == false)
        #expect(manager.isLoadingPlaylists == false)
        #expect(manager.isLoadingAlbums == false)
        #expect(manager.isLoadingStarred == false)
        #expect(manager.artistsErrorMessage.isEmpty)
        #expect(manager.playlistsErrorMessage.isEmpty)
        #expect(manager.albumsErrorMessage.isEmpty)
        #expect(manager.starredErrorMessage.isEmpty)
        #expect(manager.albumOffset == 0)
        #expect(manager.hasMoreAlbums)
        #expect(manager.hasEarlierAlbums == false)
        #expect(manager.albumListType == "newest")
    }

    private func song(id: String) -> Song {
        Song(
            id: id,
            title: "Song \(id)",
            album: "Album",
            albumId: "album",
            artist: "Artist",
            artistId: "artist",
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
