//
//  PlaylistsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct PlaylistsView: View {
    @State private var playlists: [PlaylistSummary] = []
    @State private var isLoading = false
    @State private var isSyncing = false
    @State private var errorMessage = ""
    @State private var searchText = ""
    @State private var showingSearchSheet = false
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var filteredPlaylists: [PlaylistSummary] {
        if searchText.isEmpty {
            return playlists
        }
        return playlists.filter { playlist in
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
        ZStack {
            if offlineMode {
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
                                    AsyncImage(url: coverURL) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray
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
            } else if playlists.isEmpty && isLoading {
                ProgressView("Loading playlists...")
            } else if !errorMessage.isEmpty && playlists.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadPlaylists()
                    }
                }
            } else if playlists.isEmpty {
                VStack {
                    Text("No playlists")
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadPlaylists()
                    }
                }
            } else {
                List(filteredPlaylists) { playlist in
                    NavigationLink(destination: PlaylistDetailView(playlistId: playlist.id, playlistName: playlist.name)) {
                        HStack {
                            if let coverArtId = playlist.coverArt,
                               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                AsyncImage(url: coverURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray
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
        .navigationTitle("Playlists")
        .toolbar {
            if !offlineMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        syncAllPlaylists()
                    }) {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isSyncing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: {
                            showingSearchSheet = true
                        }) {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
        }
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
            if !offlineMode && playlists.isEmpty {
                loadPlaylists()
            }
        }
    }

    private func loadPlaylists() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedPlaylists = try await NavidromeAPI.shared.getPlaylists()
                await MainActor.run {
                    self.playlists = fetchedPlaylists
                    self.isLoading = false
                    // Cache playlists for offline mode
                    self.downloadManager.cachePlaylists(fetchedPlaylists)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func syncAllPlaylists() {
        isSyncing = true

        Task {
            do {
                // First, get all playlists
                let fetchedPlaylists = try await NavidromeAPI.shared.getPlaylists()
                await MainActor.run {
                    self.playlists = fetchedPlaylists
                    self.downloadManager.cachePlaylists(fetchedPlaylists)
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
                    self.errorMessage = error.localizedDescription
                    self.isSyncing = false
                }
                print("❌ Failed to sync playlists: \(error)")
            }
        }
    }
}

#Preview {
    NavigationView {
        PlaylistsView()
    }
}
