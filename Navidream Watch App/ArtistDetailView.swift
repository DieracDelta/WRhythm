//
//  ArtistDetailView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ArtistDetailView: View {
    let artistId: String
    let artistName: String

    @State private var artist: ArtistWithAlbums?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var player: AudioPlayer { AudioPlayer.shared }

    private func filteredAlbums(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        if offlineMode {
            return albums.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
        }
        return albums
    }

    var body: some View {
        Group {
            if offlineMode {
                // Offline mode: show downloaded albums for this artist
                let downloadedAlbums = downloadManager.getDownloadedAlbums().filter { $0.artist == artistName }
                ScrollView {
                    VStack(spacing: 12) {
                        Text(artistName)
                            .font(.headline)

                        Text("\(downloadedAlbums.count) album\(downloadedAlbums.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !downloadedAlbums.isEmpty {
                            Divider()

                            VStack(spacing: 8) {
                                ForEach(downloadedAlbums, id: \.id) { album in
                                    NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                        HStack {
                                            if let coverArtId = album.coverArt,
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
                                            }

                                            VStack(alignment: .leading) {
                                                Text(album.name)
                                                    .font(.caption)
                                                    .lineLimit(1)
                                            }

                                            Spacer()

                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            VStack {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("No downloaded albums")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                    .padding()
                }
            } else if isLoading {
                ProgressView("Loading albums...")
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadArtist()
                    }
                }
            } else if let artist = artist {
                ScrollView {
                    VStack(spacing: 12) {
                        Text(artistName)
                            .font(.headline)

                        let albumsToShow = filteredAlbums(artist.album)
                        Text("\(albumsToShow.count) albums")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                playAllSongs(artist)
                            }) {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: {
                                shuffleAllSongs(artist)
                            }) {
                                Image(systemName: "shuffle")
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            if isArtistDownloaded(artist) {
                                Button(action: {
                                    deleteArtist(artist)
                                }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            } else {
                                Button(action: {
                                    downloadArtist(artist)
                                }) {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Divider()

                        VStack(spacing: 8) {
                            ForEach(filteredAlbums(artist.album)) { album in
                                NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                    HStack {
                                        if let coverArtId = album.coverArt,
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
                                        }

                                        VStack(alignment: .leading) {
                                            Text(album.name)
                                                .font(.caption)
                                                .lineLimit(1)
                                            if let year = album.year {
                                                Text(String(year))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        if isAlbumDownloaded(album.id) {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(artistName)
        .onAppear {
            if !offlineMode {
                loadArtist()
            }
        }
    }

    private func loadArtist() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedArtist = try await NavidromeAPI.shared.getArtist(id: artistId)
                await MainActor.run {
                    self.artist = fetchedArtist
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func isAlbumDownloaded(_ albumId: String) -> Bool {
        // Check if any song from this album is downloaded
        return downloadManager.downloadedSongs.values.contains { song in
            guard let album = song.album else { return false }
            return album == albumId
        }
    }

    private func isArtistDownloaded(_ artist: ArtistWithAlbums) -> Bool {
        // Check if at least one album has downloaded songs
        return artist.album.contains { isAlbumDownloaded($0.id) }
    }

    private func downloadArtist(_ artist: ArtistWithAlbums) {
        Task {
            await downloadManager.downloadArtist(artist)
        }
    }

    private func deleteArtist(_ artist: ArtistWithAlbums) {
        Task {
            for albumSummary in artist.album {
                do {
                    let album = try await NavidromeAPI.shared.getAlbum(id: albumSummary.id)
                    await MainActor.run {
                        downloadManager.deleteAlbum(album)
                    }
                } catch {
                    print("❌ Failed to fetch album \(albumSummary.name) for deletion: \(error)")
                }
            }
        }
    }

    private func playAllSongs(_ artist: ArtistWithAlbums) {
        Task {
            var allSongs: [Song] = []

            // Fetch all songs from all albums
            for albumSummary in artist.album {
                do {
                    let album = try await NavidromeAPI.shared.getAlbum(id: albumSummary.id)
                    allSongs.append(contentsOf: album.song)
                } catch {
                    print("❌ Failed to fetch album \(albumSummary.name): \(error)")
                }
            }

            guard !allSongs.isEmpty else {
                print("⚠️ No songs found for artist")
                return
            }

            await MainActor.run {
                player.playQueue(allSongs, startingAt: 0)
            }
        }
    }

    private func shuffleAllSongs(_ artist: ArtistWithAlbums) {
        Task {
            var allSongs: [Song] = []

            // Fetch all songs from all albums
            for albumSummary in artist.album {
                do {
                    let album = try await NavidromeAPI.shared.getAlbum(id: albumSummary.id)
                    allSongs.append(contentsOf: album.song)
                } catch {
                    print("❌ Failed to fetch album \(albumSummary.name): \(error)")
                }
            }

            guard !allSongs.isEmpty else {
                print("⚠️ No songs found for artist")
                return
            }

            await MainActor.run {
                player.playQueueShuffled(allSongs)
            }
        }
    }
}
