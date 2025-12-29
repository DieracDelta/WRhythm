//
//  AlbumsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct AlbumsView: View {
    @EnvironmentObject var libraryDataManager: LibraryDataManager
    @State private var searchText = ""
    @State private var searchResults: [AlbumSummary] = []
    @State private var isSearching = false
    @State private var showingSearchSheet = false
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    private let pageSize = 20

    private var filteredAlbums: [AlbumSummary] {
        if offlineMode {
            let downloadedAlbums = libraryDataManager.albums.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
            if searchText.isEmpty {
                return downloadedAlbums
            }
            return downloadedAlbums.filter { album in
                album.name.localizedCaseInsensitiveContains(searchText) ||
                (album.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        } else {
            // Online mode: use search results if searching, otherwise show paginated list
            if !searchText.isEmpty {
                return searchResults
            }
            return libraryDataManager.albums
        }
    }

        var body: some View {

            content

                .navigationTitle("Albums")

                .toolbar {

                    if !offlineMode {

                        ToolbarItem(placement: .topBarTrailing) {

                            if !searchText.isEmpty {

                                Button(action: {

                                    searchText = ""

                                    searchResults = []

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

                            TextField("Search albums", text: $searchText)

                                .padding()

    

                            Button("Search") {

                                showingSearchSheet = false

                                performSearch(query: searchText)

                            }

                            .buttonStyle(.borderedProminent)

                            .disabled(searchText.isEmpty)

    

                            Spacer()

                        }

                        .navigationTitle("Search Albums")

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

                    if !offlineMode && libraryDataManager.albums.isEmpty {

                        libraryDataManager.fetchInitialAlbums()

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

            // Offline mode: show downloaded albums only

            let downloadedAlbums = downloadManager.getDownloadedAlbums()

            let filteredAlbums = searchText.isEmpty ? downloadedAlbums : downloadedAlbums.filter { album in

                album.name.localizedCaseInsensitiveContains(searchText) ||

                (album.artist?.localizedCaseInsensitiveContains(searchText) ?? false)

            }

            if downloadedAlbums.isEmpty {

                VStack {

                    Image(systemName: "arrow.down.circle")

                        .font(.largeTitle)

                        .foregroundColor(.secondary)

                    Text("No downloaded albums")

                        .font(.headline)

                    Text("Download albums while online to access them here")

                        .font(.caption)

                        .foregroundColor(.secondary)

                        .multilineTextAlignment(.center)

                        .padding(.horizontal)

                }

            } else if filteredAlbums.isEmpty {

                VStack {

                    Image(systemName: "magnifyingglass")

                        .font(.largeTitle)

                        .foregroundColor(.secondary)

                    Text("No albums found")

                        .font(.headline)

                    Text("Try a different search term")

                        .font(.caption)

                        .foregroundColor(.secondary)

                }

            } else {

                List {

                    ForEach(filteredAlbums, id: \.id) { album in

                        NavigationLink(destination: AlbumDetailView(albumId: album.id)) {

                            HStack {

                                if let coverArtId = album.coverArt,

                                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {

                                    CachedAsyncImage(url: coverURL) { image in

                                        image

                                            .resizable()

                                            .aspectRatio(contentMode: .fill)

                                    }

                                    .frame(width: 40, height: 40)

                                    .cornerRadius(4)

                                    .id(coverURL)

                                }

    

                                VStack(alignment: .leading) {

                                    Text(album.name)

                                        .font(.headline)

                                        .lineLimit(1)

                                    if let artist = album.artist {

                                        Text(artist)

                                            .font(.caption)

                                            .foregroundColor(.secondary)

                                            .lineLimit(1)

                                    }

                                }

    

                                Spacer()

    

                                Image(systemName: "arrow.down.circle.fill")

                                    .font(.caption2)

                                    .foregroundColor(.green)

                            }

                        }

                    }

                }

                .searchable(text: $searchText, prompt: "Search albums")

            }

        }

    

        @ViewBuilder

        private var onlineContent: some View {

            if libraryDataManager.albums.isEmpty && libraryDataManager.isLoadingAlbums {

                VStack(spacing: 8) {

                    ProgressView("Loading albums...")

                    Text("Please wait...")

                        .font(.caption)

                        .foregroundColor(.secondary)

                }

            } else if !libraryDataManager.albumsErrorMessage.isEmpty && libraryDataManager.albums.isEmpty {

                VStack {

                    Text("Error")

                        .font(.headline)

                    Text(libraryDataManager.albumsErrorMessage)

                        .font(.caption)

                        .foregroundColor(.red)

                    Button("Retry") {

                        libraryDataManager.fetchInitialAlbums(forceRefresh: true)

                    }

                }

            } else if libraryDataManager.albums.isEmpty {

                VStack {

                    Text("No albums found")

                        .foregroundColor(.secondary)

                    Button("Retry") {

                        libraryDataManager.fetchInitialAlbums(forceRefresh: true)

                    }

                }

            } else {

                List {

                    ForEach(filteredAlbums) { album in

                        NavigationLink(destination: AlbumDetailView(albumId: album.id)) {

                            HStack {

                                if let coverArtId = album.coverArt,

                                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {

                                    CachedAsyncImage(url: coverURL) { image in

                                        image

                                            .resizable()

                                            .aspectRatio(contentMode: .fill)

                                    }

                                    .frame(width: 40, height: 40)

                                    .cornerRadius(4)

                                        .id(coverURL)

                                }

    

                                VStack(alignment: .leading) {

                                    Text(album.name)

                                        .font(.headline)

                                        .lineLimit(1)

                                    if let artist = album.artist {

                                        Text(artist)

                                            .font(.caption)

                                            .foregroundColor(.secondary)

                                            .lineLimit(1)

                                    }

                                }

                            }

                        }

                        .onAppear {

                            if album.id == libraryDataManager.albums.last?.id && libraryDataManager.hasMoreAlbums && !libraryDataManager.isLoadingAlbums {

                                libraryDataManager.fetchMoreAlbums()

                            }

                        }

                    }

    

                    if libraryDataManager.isLoadingAlbums {

                        HStack {

                            Spacer()

                            ProgressView()

                            Spacer()

                        }

                    }

                }

            }

        }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard query == searchText else { return }

            isSearching = true

            do {
                let result = try await NavidromeAPI.shared.search(query: query)
                await MainActor.run {
                    self.searchResults = result.album ?? []
                    self.isSearching = false
                    print("🔍 Album search results: \(self.searchResults.count) albums")
                }
            }
            catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                    print("❌ Album search error: \(error)")
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        AlbumsView()
    }
}
