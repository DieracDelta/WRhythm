//
//  ArtistsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ArtistsView: View {
    @State private var artists: [Artist] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var displayedArtists: [Artist] = []
    @State private var loadedCount = 0
    private let batchSize = 20

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading artists...")
                    Text("Please wait...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadArtists()
                    }
                }
            } else if displayedArtists.isEmpty {
                VStack {
                    Text("No artists found")
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadArtists()
                    }
                }
            } else {
                List {
                    ForEach(displayedArtists) { artist in
                        NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                            HStack {
                                if let coverArtId = artist.coverArt,
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
                                    Text(artist.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let albumCount = artist.albumCount {
                                        Text("\(albumCount) albums")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            if artist.id == displayedArtists.last?.id {
                                loadMoreArtists()
                            }
                        }
                    }

                    if loadedCount < artists.count {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .onAppear {
                            loadMoreArtists()
                        }
                    }
                }
            }
        }
        .navigationTitle("Artists (\(displayedArtists.count))")
        .onAppear {
            loadArtists()
        }
    }

    private func loadArtists() {
        isLoading = true
        errorMessage = ""
        displayedArtists = []
        loadedCount = 0

        print("🎵 ArtistsView: Starting to load artists...")

        Task {
            do {
                let fetchedArtists = try await NavidromeAPI.shared.getArtists()
                await MainActor.run {
                    print("🎵 ArtistsView: Successfully loaded \(fetchedArtists.count) artists")
                    self.artists = fetchedArtists
                    self.isLoading = false

                    // Load first batch immediately
                    loadMoreArtists()
                }
            } catch {
                await MainActor.run {
                    print("❌ ArtistsView: Failed to load artists - \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func loadMoreArtists() {
        guard loadedCount < artists.count else { return }

        let nextBatch = artists[loadedCount..<min(loadedCount + batchSize, artists.count)]
        print("📦 Loading batch: \(loadedCount) to \(loadedCount + nextBatch.count)")

        displayedArtists.append(contentsOf: nextBatch)
        loadedCount += nextBatch.count

        print("✅ Now displaying \(displayedArtists.count) of \(artists.count) artists")
    }
}

#Preview {
    NavigationView {
        ArtistsView()
    }
}
