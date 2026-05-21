//
//  LibraryDataManager.swift
//  WRhythm Watch App
//
//  Created by Gemini Agent on 12/29/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
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
