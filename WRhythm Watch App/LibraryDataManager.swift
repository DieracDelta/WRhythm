//
//  LibraryDataManager.swift
//  WRhythm Watch App
//
//  Created by Gemini Agent on 12/29/25.
//

import Foundation
import SwiftUI
import Combine

struct AsyncResultOwnershipPolicy: Sendable {
    static func shouldApply(capturedGeneration: Int, currentGeneration: Int, isCancelled: Bool) -> Bool {
        !isCancelled && capturedGeneration == currentGeneration
    }
}

struct SearchResultOwnershipPolicy: Sendable {
    static func shouldApply(query: String, currentQuery: String, isCancelled: Bool) -> Bool {
        !isCancelled && query == currentQuery
    }
}

struct SearchRetryPolicy: Sendable {
    static func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    static func userMessage(for error: Error) -> String {
        if isRetryable(error) {
            return "Search failed after retrying. Check the server connection and try again."
        }
        return error.localizedDescription
    }
}

nonisolated struct SearchPaginationPolicy: Sendable {
    static let defaultPageSize = 20

    static func sanitizedPageSize(_ pageSize: Int) -> Int {
        max(1, pageSize)
    }

    static func offset(forPage page: Int, pageSize: Int = defaultPageSize) -> Int {
        max(0, page) * sanitizedPageSize(pageSize)
    }

    static func canGoPrevious(page: Int) -> Bool {
        page > 0
    }

    static func canGoNext(resultCount: Int, pageSize: Int = defaultPageSize) -> Bool {
        resultCount >= sanitizedPageSize(pageSize)
    }

    static func visiblePages(currentPage: Int, canGoNext _: Bool, radius: Int = 2) -> [Int] {
        let currentPage = max(0, currentPage)
        let lowerBound = max(0, currentPage - max(0, radius))
        return Array(lowerBound...currentPage)
    }
}

nonisolated enum AudioMuseSearchResultLimitPolicy: Sendable {
    static let defaultLimit = SearchPaginationPolicy.defaultPageSize
    static let minimumLimit = 5
    static let maximumLimit = 200
    static let step = 5

    static func sanitizedLimit(_ limit: Int) -> Int {
        min(max(limit, minimumLimit), maximumLimit)
    }
}

nonisolated enum AlbumMetadataPagingPolicy: Sendable {
    static func maxLoadedPages(forRenderedLimit _: Int?) -> Int? {
        nil
    }
}

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
    @Published var hasEarlierAlbums = false
    @Published var albumListType = "newest"
    
    // MARK: - Favourites
    @Published var starred: StarredContent?
    @Published var isLoadingStarred = false
    @Published var starredErrorMessage = ""
    
    private static let albumPageSize = 20
    private let pageSize = LibraryDataManager.albumPageSize
    private var artistsFetchTask: Task<Void, Never>?
    private var playlistsFetchTask: Task<Void, Never>?
    private var albumsFetchTask: Task<Void, Never>?
    private var starredFetchTask: Task<Void, Never>?
    private var artistsFetchGeneration = 0
    private var playlistsFetchGeneration = 0
    private var albumsFetchGeneration = 0
    private var starredFetchGeneration = 0
    private var cancellables = Set<AnyCancellable>()
    private var albumPageCache = PagedCollectionCache<AlbumSummary>(
        pageSize: LibraryDataManager.albumPageSize,
        maxLoadedPages: LibraryDataManager.albumMaxLoadedPages()
    )

    init() {
        NotificationCenter.default.publisher(for: .wrhythmAccountLocalDataDidReset)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearAccountBoundData()
            }
            .store(in: &cancellables)
    }

    func clearAccountBoundData() {
        artistsFetchTask?.cancel()
        playlistsFetchTask?.cancel()
        albumsFetchTask?.cancel()
        starredFetchTask?.cancel()

        artistsFetchGeneration += 1
        playlistsFetchGeneration += 1
        albumsFetchGeneration += 1
        starredFetchGeneration += 1

        artists = []
        playlists = []
        albums = []
        starred = nil

        isLoadingArtists = false
        isLoadingPlaylists = false
        isLoadingAlbums = false
        isLoadingStarred = false

        artistsErrorMessage = ""
        playlistsErrorMessage = ""
        albumsErrorMessage = ""
        starredErrorMessage = ""

        albumOffset = 0
        hasMoreAlbums = true
        hasEarlierAlbums = false
        albumListType = "newest"
        resetAlbumPageCache()
    }
    
    // MARK: - Artists Methods
    func fetchArtists(forceRefresh: Bool = false) {
        guard !isLoadingArtists else { return }
        if !artists.isEmpty && !forceRefresh { return }
        
        isLoadingArtists = true
        artistsErrorMessage = ""
        artistsFetchGeneration += 1
        let generation = artistsFetchGeneration
        artistsFetchTask?.cancel()
        
        artistsFetchTask = Task { @MainActor in
            do {
                let fetchedArtists = try await NavidromeAPI.shared.getArtists()
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.artistsFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.artists = fetchedArtists
                self.isLoadingArtists = false
            } catch {
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.artistsFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.artistsErrorMessage = error.localizedDescription
                self.isLoadingArtists = false
            }
        }
    }
    
    // MARK: - Playlists Methods
    func fetchPlaylists(forceRefresh: Bool = false) {
        guard !isLoadingPlaylists else { return }
        if !playlists.isEmpty && !forceRefresh { return }
        
        isLoadingPlaylists = true
        playlistsErrorMessage = ""
        playlistsFetchGeneration += 1
        let generation = playlistsFetchGeneration
        playlistsFetchTask?.cancel()
        
        playlistsFetchTask = Task { @MainActor in
            do {
                let fetchedPlaylists = try await NavidromeAPI.shared.getPlaylists()
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.playlistsFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.playlists = fetchedPlaylists
                self.isLoadingPlaylists = false
                // Also update offline cache
                DownloadManager.shared.cachePlaylists(fetchedPlaylists)
            } catch {
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.playlistsFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.playlistsErrorMessage = error.localizedDescription
                self.isLoadingPlaylists = false
            }
        }
    }
    
    // MARK: - Albums Methods
    func fetchInitialAlbums(forceRefresh: Bool = false, type: String = "newest") {
        if isLoadingAlbums {
            guard forceRefresh || albumListType != type else { return }
            albumsFetchTask?.cancel()
            isLoadingAlbums = false
        }
        if !albums.isEmpty && !forceRefresh && albumListType == type { return }
        
        albums = []
        albumOffset = 0
        hasMoreAlbums = true
        hasEarlierAlbums = false
        albumListType = type
        albumsErrorMessage = ""
        albumsFetchTask?.cancel()
        albumsFetchGeneration += 1
        resetAlbumPageCache()
        
        fetchMoreAlbums()
    }

    func fetchMoreAlbums() {
        guard !isLoadingAlbums && hasMoreAlbums else { return }
        
        isLoadingAlbums = true
        let generation = albumsFetchGeneration
        let pageIndex = albumPageCache.nextPageIndex
        let offset = pageIndex * pageSize
        
        albumsFetchTask = Task { @MainActor in
            do {
                let fetchedAlbums = try await NavidromeAPI.shared.getAlbumList(
                    type: self.albumListType,
                    size: pageSize,
                    offset: offset
                )
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.albumsFetchGeneration,
                    isCancelled: Task.isCancelled
                ), self.albumPageCache.nextPageIndex == pageIndex else { return }
                self.albumPageCache.storePage(
                    index: pageIndex,
                    elements: fetchedAlbums,
                    hasMoreAfterPage: fetchedAlbums.count >= self.pageSize
                )
                self.syncAlbumWindowFromCache()
                self.isLoadingAlbums = false
            } catch {
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.albumsFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.albumsErrorMessage = error.localizedDescription
                self.isLoadingAlbums = false
            }
        }
    }

    func fetchPreviousAlbums() {
        guard !isLoadingAlbums, let pageIndex = albumPageCache.previousPageIndex else { return }

        isLoadingAlbums = true
        let generation = albumsFetchGeneration
        let offset = pageIndex * pageSize

        albumsFetchTask = Task { @MainActor in
            do {
                let fetchedAlbums = try await NavidromeAPI.shared.getAlbumList(
                    type: self.albumListType,
                    size: self.pageSize,
                    offset: offset
                )
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.albumsFetchGeneration,
                    isCancelled: Task.isCancelled
                ), self.albumPageCache.previousPageIndex == pageIndex else { return }

                self.albumPageCache.storePage(
                    index: pageIndex,
                    elements: fetchedAlbums,
                    hasMoreAfterPage: true
                )
                self.syncAlbumWindowFromCache()
                self.isLoadingAlbums = false
            } catch {
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.albumsFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.albumsErrorMessage = error.localizedDescription
                self.isLoadingAlbums = false
            }
        }
    }

    private static func albumMaxLoadedPages() -> Int? {
        let storedValue = UserDefaults.standard.object(forKey: SongRenderWindowPolicy.userDefaultsKey) as? Int
            ?? SongRenderWindowPolicy.defaultLimit
        return AlbumMetadataPagingPolicy.maxLoadedPages(
            forRenderedLimit: SongRenderWindowPolicy.effectiveLimit(storedValue)
        )
    }

    private func resetAlbumPageCache() {
        albumPageCache = PagedCollectionCache(
            pageSize: pageSize,
            maxLoadedPages: Self.albumMaxLoadedPages()
        )
        syncAlbumWindowFromCache()
    }

    private func syncAlbumWindowFromCache() {
        albums = albumPageCache.elements
        albumOffset = albumPageCache.nextOffset
        hasMoreAlbums = albumPageCache.hasMoreAfter
        hasEarlierAlbums = albumPageCache.hasLoadedPreviousPage
    }
    
    // MARK: - Favourites Methods
    func fetchStarred(forceRefresh: Bool = false) {
        guard !isLoadingStarred else { return }
        if starred != nil && !forceRefresh { return }
        
        isLoadingStarred = true
        starredErrorMessage = ""
        starredFetchGeneration += 1
        let generation = starredFetchGeneration
        starredFetchTask?.cancel()
        
        starredFetchTask = Task { @MainActor in
            do {
                let fetchedStarred = try await NavidromeAPI.shared.getStarred()
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.starredFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.starred = fetchedStarred
                self.isLoadingStarred = false
            } catch {
                guard AsyncResultOwnershipPolicy.shouldApply(
                    capturedGeneration: generation,
                    currentGeneration: self.starredFetchGeneration,
                    isCancelled: Task.isCancelled
                ) else { return }
                self.starredErrorMessage = error.localizedDescription
                self.isLoadingStarred = false
            }
        }
    }
}
