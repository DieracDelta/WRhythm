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
    @State private var showingSearchSheet = false
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    private let viewIdentifier = CachedView.playlists

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
                HStack(spacing: 16) {
                    Button(action: {
                        syncAllPlaylists()
                    }) {
                        if isSyncing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("🔄")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncing)

                    Button(action: {
                        showingSearchSheet = true
                    }) {
                        Text("🔍")
                            .font(.title3)
                    }
                    .buttonStyle(.bordered)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Text("✕")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            content
        }
        .navigationTitle("Playlists")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSearchSheet) {
            NavigationView {
                VStack(spacing: 16) {
                    TextField("Search playlists", text: $searchText)
                        .padding()

                    Button("Search") {
                        showingSearchSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.isEmpty)

                    Spacer()
                }
                .navigationTitle("Search Playlists")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingSearchSheet = false
                        }
                    }
                }
            }
        }
        .onAppear {
            ViewCacheManager.shared.recordViewAccess(viewIdentifier)
            if !offlineMode {
                libraryDataManager.fetchPlaylists()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .evictViewCache)) { notification in
            if let view = notification.userInfo?["view"] as? CachedView,
               view == viewIdentifier {
                clearCache()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearAllViewCaches)) { _ in
            clearCache()
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
            VStack {
                Image(systemName: "music.note.list")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No cached playlists")
                    .font(.headline)
                Text("View playlists while online to cache them")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        } else {
            List(filteredCachedPlaylists, id: \.id) { playlist in
                NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                    HStack {
                        if let coverArtId = playlist.coverArt,
                           let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                            CachedAsyncImage(url: coverURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)
                            .id(coverURL)
                        } else {
                            ZStack {
                                Color.gray
                                Image(systemName: "music.note.list")
                                    .foregroundColor(.white)
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)
                        }

                        VStack(alignment: .leading) {
                            Text(playlist.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(playlist.songCount) songs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search playlists")
        }
    }

    @ViewBuilder
    private var onlineContent: some View {
        if libraryDataManager.playlists.isEmpty && libraryDataManager.isLoadingPlaylists {
            ProgressView("Loading playlists...")
        } else if !libraryDataManager.playlistsErrorMessage.isEmpty && libraryDataManager.playlists.isEmpty {
            VStack {
                Text("Error")
                    .font(.headline)
                Text(libraryDataManager.playlistsErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                Button("Retry") {
                    libraryDataManager.fetchPlaylists(forceRefresh: true)
                }
            }
        } else if libraryDataManager.playlists.isEmpty {
            VStack {
                Text("No playlists")
                    .foregroundColor(.secondary)
                Button("Retry") {
                    libraryDataManager.fetchPlaylists(forceRefresh: true)
                }
            }
        } else {
            List(filteredPlaylists) { playlist in
                NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                    HStack {
                        if let coverArtId = playlist.coverArt,
                           let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                            CachedAsyncImage(url: coverURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)
                            .id(coverURL)
                        } else {
                            ZStack {
                                Color.gray
                                Image(systemName: "music.note.list")
                                    .foregroundColor(.white)
                            }
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)
                        }

                        VStack(alignment: .leading) {
                            Text(playlist.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(playlist.songCount) songs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
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

    private func clearCache() {
        print("🗑️ Clearing \(viewIdentifier.rawValue) cache")
        // Playlists cache is managed by LibraryDataManager, just clear search
        searchText = ""
    }
}

#Preview {
    NavigationView {
        PlaylistsView()
    }
}
