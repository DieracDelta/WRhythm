//
//  PlaylistsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var libraryDataManager: LibraryDataManager
    @State private var isSyncing = false
    @State private var searchText = ""
    @State private var presentedSheet: PlaylistsSheet?
    @State private var sortOption: PlaylistSortOption = .nameAscending
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var filteredPlaylists: [PlaylistSummary] {
        if searchText.isEmpty {
            return libraryDataManager.playlists
        }
        return libraryDataManager.playlists.filter { playlist in
            playlist.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredCachedPlaylists: [CachedPlaylist] {
        if searchText.isEmpty {
            return downloadManager.cachedPlaylists
        }
        return downloadManager.cachedPlaylists.filter { playlist in
            playlist.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WRhythmActionBar {
                WRhythmSortMenu(selection: $sortOption)

                if !offlineMode {
                    Button(action: {
                        syncAllPlaylists()
                    }) {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncing)

                    Button(action: {
                        presentedSheet = .search
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            content
        }
        .navigationTitle("Playlists")
        .wrhythmPageBackground()
        .platformNavigationBarTitleDisplayModeInline()
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .search:
                PlatformSearchSheet("Search Playlists", onCancel: {
                    presentedSheet = nil
                }) {
                    VStack(spacing: 16) {
                        TextField("Search playlists", text: $searchText)
                            .platformSearchTextFieldStyle()
                            .wrhythmDismissFocusOnEscape()
                            .frame(maxWidth: .infinity)

                        Button("Search") {
                            presentedSheet = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(searchText.isEmpty)

                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            if !offlineMode {
                libraryDataManager.fetchPlaylists()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if offlineMode {
            offlineContent
        } else {
            onlineContent
        }
    }

    @ViewBuilder
    private var offlineContent: some View {
        let sortedPlaylists = sortedCachedPlaylists(filteredCachedPlaylists)
        let resetToken = SongRenderWindowPolicy.resetToken(
            scope: "offlinePlaylists",
            sortIdentifier: sortOption.rawValue,
            query: searchText
        )

        if filteredCachedPlaylists.isEmpty {
            WRhythmEmptyState(
                systemImage: "music.note.list",
                title: "No cached playlists",
                message: "View playlists while online to cache them"
            )
        } else {
            ScrollView {
                VStack(spacing: WRhythmSpacing.sm) {
#if os(iOS)
                    PhoneSearchSubmenuHeader(
                        title: "Offline Playlists",
                        subtitle: "Cached playlists ready for offline playback.",
                        systemImage: "music.note.list",
                        countText: playlistCountText(sortedPlaylists.count),
                        queryText: searchText
                    )
#endif

                    WRhythmCard {
                        SlidingRenderWindowForEach(sortedPlaylists, estimatedRowHeight: 64, resetToken: resetToken) { _, playlist in
                            NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                                WRhythmCollectionRow(
                                    title: playlist.name,
                                    subtitle: "\(playlist.songCount) songs",
                                    detail: "Cached",
                                    coverArtId: playlist.coverArt,
                                    fallbackSystemImage: "music.note.list",
                                    tint: WRhythmTheme.playlistGen
                                ) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(WRhythmTypography.metadata)
                                        .foregroundColor(WRhythmTheme.success)
                                }
                            }
                            .buttonStyle(.plain)
                            .wrhythmPlaylistActions(playlistId: playlist.id, playlistName: playlist.name)

                            if playlist.id != sortedPlaylists.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search playlists")
            .wrhythmListSurface()
        }
    }

    @ViewBuilder
    private var onlineContent: some View {
        if libraryDataManager.playlists.isEmpty && libraryDataManager.isLoadingPlaylists {
            WRhythmLoadingState(
                systemImage: "music.note.list",
                title: "Loading playlists",
                message: nil
            )
        } else if !libraryDataManager.playlistsErrorMessage.isEmpty && libraryDataManager.playlists.isEmpty {
            WRhythmErrorState(
                title: "Playlist Error",
                message: libraryDataManager.playlistsErrorMessage
            ) {
                libraryDataManager.fetchPlaylists(forceRefresh: true)
            }
        } else if libraryDataManager.playlists.isEmpty {
            WRhythmEmptyState(
                systemImage: "music.note.list",
                title: "No playlists",
                message: nil,
                actionTitle: "Retry",
                action: {
                    libraryDataManager.fetchPlaylists(forceRefresh: true)
                }
            )
        } else {
            let sortedPlaylists = sortOption.sorted(filteredPlaylists)
            let resetToken = SongRenderWindowPolicy.resetToken(
                scope: "playlists",
                sortIdentifier: sortOption.rawValue,
                query: searchText
            )
            ScrollView {
                VStack(spacing: WRhythmSpacing.sm) {
#if os(iOS)
                    PhoneSearchSubmenuHeader(
                        title: "Playlists",
                        subtitle: searchText.isEmpty ? "Mixes and saved queues from your library." : "Playlists matching your search.",
                        systemImage: "music.note.list",
                        countText: playlistCountText(sortedPlaylists.count),
                        queryText: searchText
                    )
#endif

                    WRhythmCard {
                        SlidingRenderWindowForEach(sortedPlaylists, estimatedRowHeight: 64, resetToken: resetToken) { _, playlist in
                            NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                                WRhythmCollectionRow(
                                    title: playlist.name,
                                    subtitle: "\(playlist.songCount) songs",
                                    coverArtId: playlist.coverArt,
                                    fallbackSystemImage: "music.note.list",
                                    tint: WRhythmTheme.playlistGen
                                )
                            }
                            .buttonStyle(.plain)
                            .wrhythmPlaylistActions(playlistId: playlist.id, playlistName: playlist.name)

                            if playlist.id != sortedPlaylists.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .wrhythmListSurface()
        }
    }

    private func playlistCountText(_ count: Int) -> String {
        count == 1 ? "1 playlist" : "\(count) playlists"
    }

    private func sortedCachedPlaylists(_ playlists: [CachedPlaylist]) -> [CachedPlaylist] {
        playlists.sorted { lhs, rhs in
            switch sortOption {
            case .nameAscending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return rhs.name.localizedCaseInsensitiveCompare(lhs.name) == .orderedAscending
            case .recentlyChanged:
                return lhs.cachedAt == rhs.cachedAt ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending : lhs.cachedAt > rhs.cachedAt
            case .mostTracks:
                return lhs.songCount == rhs.songCount ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending : lhs.songCount > rhs.songCount
            case .fewestTracks:
                return lhs.songCount == rhs.songCount ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending : lhs.songCount < rhs.songCount
            }
        }
    }

    private func syncAllPlaylists() {
        isSyncing = true

        Task {
            libraryDataManager.fetchPlaylists(forceRefresh: true)

            do {
                let fetchedPlaylists = try await NavidromeAPI.shared.getPlaylists()
                await MainActor.run {
                    libraryDataManager.playlists = fetchedPlaylists
                    downloadManager.cachePlaylists(fetchedPlaylists)
                }

                for playlist in fetchedPlaylists {
                    do {
                        let fullPlaylist = try await NavidromeAPI.shared.getPlaylist(id: playlist.id)
                        await MainActor.run {
                            self.downloadManager.cachePlaylistDetails(fullPlaylist)
                        }
                        print("✅ Synced playlist: \(playlist.name)")
                    } catch {
                        print("❌ Failed to sync playlist \(playlist.name): \(error)")
                    }
                }

                await MainActor.run {
                    self.isSyncing = false
                }
                print("✅ All playlists synced")
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                }
                print("❌ Failed to sync playlists: \(error)")
            }
        }
    }
}

private enum PlaylistsSheet: String, Identifiable {
    case search

    var id: String { rawValue }
}

#Preview {
    NavigationStack {
        PlaylistsView()
    }
}
