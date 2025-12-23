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
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if playlists.isEmpty && isLoading {
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
                List(playlists) { playlist in
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
        .onAppear {
            if playlists.isEmpty {
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

#Preview {
    NavigationView {
        PlaylistsView()
    }
}
