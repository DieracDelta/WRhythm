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
            // Action buttons at top when online
            if !offlineMode {
                WRhythmActionBar {
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
        // Offline mode: show cached playlists
        if filteredCachedPlaylists.isEmpty {
            WRhythmEmptyState(
                systemImage: "music.note.list",
                title: "No cached playlists",
                message: "View playlists while online to cache them"
            )
        } else {
            List(filteredCachedPlaylists, id: \.id) { playlist in
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
                            .font(.caption2)
                            .foregroundColor(WRhythmTheme.success)
                    }
                }
                .wrhythmPlaylistActions(playlistId: playlist.id, playlistName: playlist.name)
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
                actionTitle: "Retry"
            ) {
                    libraryDataManager.fetchPlaylists(forceRefresh: true)
            }
        } else {
            List(filteredPlaylists) { playlist in
                NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                    WRhythmCollectionRow(
                        title: playlist.name,
                        subtitle: "\(playlist.songCount) songs",
                        coverArtId: playlist.coverArt,
                        fallbackSystemImage: "music.note.list",
                        tint: WRhythmTheme.playlistGen
                    )
                }
                .wrhythmPlaylistActions(playlistId: playlist.id, playlistName: playlist.name)
            }
            .wrhythmListSurface()
        }
    }

    private func syncAllPlaylists() {
        isSyncing = true

        Task {
            // Refresh playlists first
            libraryDataManager.fetchPlaylists(forceRefresh: true)
            
            // Wait a bit for playlists to update (fetchPlaylists is async but we don't await it here directly as it's on main actor via func, 
            // but the network call is in Task. We need to wait for it.)
            // Actually LibraryDataManager.fetchPlaylists launches a Task. We can't await it easily unless we change the signature.
            // For now, let's just fetch manually here to ensure we have the latest list to iterate.
            
            do {
                let fetchedPlaylists = try await NavidromeAPI.shared.getPlaylists()
                await MainActor.run {
                    libraryDataManager.playlists = fetchedPlaylists
                    // Cache playlists for offline mode
                    downloadManager.cachePlaylists(fetchedPlaylists)
                }

                // Then, fetch full details for each playlist to cache song IDs
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
    NavigationView {
        PlaylistsView()
    }
}
