//
//  LibraryDataManager.swift
//  WRhythm Watch App
//
//  Created by Gemini Agent on 12/29/25.
//

import Foundation
import SwiftUI
import Combine

final class LibraryDataManager: ObservableObject {
    // MARK: - Artists
    @Published var artists: [Artist] = []
    @Published var isLoadingArtists = false
    @Published var artistsErrorMessage = ""

    // MARK: - Playlists
    @Published var playlists: [PlaylistSummary] = []
    @Published var isLoadingPlaylists = false
    @Published var playlistsErrorMessage = ""

    // MARK: - Albums
    @Published var albums: [AlbumSummary] = []
    @Published var isLoadingAlbums = false
    @Published var albumsErrorMessage = ""
    @Published var albumOffset = 0
    @Published var hasMoreAlbums = true

    // MARK: - Favourites
    @Published var starred: StarredContent?
    @Published var isLoadingStarred = false
    @Published var starredErrorMessage = ""

    private let pageSize = 20

    // MARK: - Battery Saver Cache Limits
    private var maxArtists: Int {
        BatterySaverManager.shared.isActive ? 100 : Int.max
    }

    private var maxAlbums: Int {
        BatterySaverManager.shared.isActive ? 50 : Int.max
    }
    
    // MARK: - Artists Methods
    func fetchArtists(forceRefresh: Bool = false) {
        guard !isLoadingArtists else { return }
        if !artists.isEmpty && !forceRefresh { return }
        
        isLoadingArtists = true
        artistsErrorMessage = ""
        
        Task {
            do {
                let fetchedArtists = try await NavidromeAPI.shared.getArtists()
                await MainActor.run {
                    self.artists = fetchedArtists

                    // Enforce limit if battery saver active
                    if BatterySaverManager.shared.isActive && self.artists.count > self.maxArtists {
                        self.artists = Array(self.artists.prefix(self.maxArtists))
                        print("🔋 Limited artists cache to \(self.maxArtists) items")
                    }

                    self.isLoadingArtists = false
                }
            } catch {
                await MainActor.run {
                    self.artistsErrorMessage = error.localizedDescription
                    self.isLoadingArtists = false
                }
            }
        }
    }
    
    // MARK: - Playlists Methods
    func fetchPlaylists(forceRefresh: Bool = false) {
        guard !isLoadingPlaylists else { return }
        if !playlists.isEmpty && !forceRefresh { return }
        
        isLoadingPlaylists = true
        playlistsErrorMessage = ""
        
        Task {
            do {
                let fetchedPlaylists = try await NavidromeAPI.shared.getPlaylists()
                await MainActor.run {
                    self.playlists = fetchedPlaylists
                    self.isLoadingPlaylists = false
                    // Also update offline cache
                    DownloadManager.shared.cachePlaylists(fetchedPlaylists)
                }
            } catch {
                await MainActor.run {
                    self.playlistsErrorMessage = error.localizedDescription
                    self.isLoadingPlaylists = false
                }
            }
        }
    }
    
    // MARK: - Albums Methods
    func fetchInitialAlbums(forceRefresh: Bool = false) {
        guard !isLoadingAlbums else { return }
        if !albums.isEmpty && !forceRefresh { return }
        
        albums = []
        albumOffset = 0
        hasMoreAlbums = true
        albumsErrorMessage = ""
        
        fetchMoreAlbums()
    }
    
    func fetchMoreAlbums() {
        guard !isLoadingAlbums && hasMoreAlbums else { return }
        
        isLoadingAlbums = true
        
        Task {
            do {
                let fetchedAlbums = try await NavidromeAPI.shared.getAlbumList(
                    type: "newest",
                    size: pageSize,
                    offset: albumOffset
                )
                
                await MainActor.run {
                    if fetchedAlbums.count < self.pageSize {
                        self.hasMoreAlbums = false
                    }

                    self.albums.append(contentsOf: fetchedAlbums)
                    self.albumOffset += fetchedAlbums.count

                    // Enforce limit if battery saver active
                    if BatterySaverManager.shared.isActive && self.albums.count > self.maxAlbums {
                        self.albums = Array(self.albums.prefix(self.maxAlbums))
                        self.hasMoreAlbums = false // Stop loading more if limit reached
                        print("🔋 Limited albums cache to \(self.maxAlbums) items")
                    }

                    self.isLoadingAlbums = false
                }
            } catch {
                await MainActor.run {
                    self.albumsErrorMessage = error.localizedDescription
                    self.isLoadingAlbums = false
                }
            }
        }
    }
    
    // MARK: - Favourites Methods
    func fetchStarred(forceRefresh: Bool = false) {
        guard !isLoadingStarred else { return }
        if starred != nil && !forceRefresh { return }
        
        isLoadingStarred = true
        starredErrorMessage = ""
        
        Task {
            do {
                let fetchedStarred = try await NavidromeAPI.shared.getStarred()
                await MainActor.run {
                    self.starred = fetchedStarred
                    self.isLoadingStarred = false
                }
            } catch {
                await MainActor.run {
                    self.starredErrorMessage = error.localizedDescription
                    self.isLoadingStarred = false
                }
            }
        }
    }
}
