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
                List(artist.album) { album in
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
                                    .font(.headline)
                                    .lineLimit(1)
                                if let year = album.year {
                                    Text(String(year))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
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
}
