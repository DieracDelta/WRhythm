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

    var body: some View {
        Group {
            if isLoading {
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

                        Text("\(artist.album.count) albums")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isArtistDownloaded(artist) {
                            Button(action: {
                                deleteArtist(artist)
                            }) {
                                Label("Delete Downloads", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        } else {
                            Button(action: {
                                downloadArtist(artist)
                            }) {
                                Label("Download All", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()

                        VStack(spacing: 8) {
                            ForEach(artist.album) { album in
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
            loadArtist()
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
}
