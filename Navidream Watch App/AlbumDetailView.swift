//
//  AlbumDetailView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct AlbumDetailView: View {
    let albumId: String

    @State private var album: Album?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading album...")
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadAlbum()
                    }
                }
            } else if let album = album {
                ScrollView {
                    VStack(spacing: 12) {
                        if let coverArtId = album.coverArt,
                           let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                            AsyncImage(url: coverURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray
                            }
                            .frame(height: 120)
                            .cornerRadius(8)
                        }

                        VStack(spacing: 4) {
                            Text(album.name)
                                .font(.headline)
                            if let artist = album.artist {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let year = album.year {
                                Text(String(year))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button(action: {
                            player.playQueue(album.song, startingAt: 0)
                        }) {
                            Label("Play All", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Divider()

                        VStack(spacing: 8) {
                            ForEach(Array(album.song.enumerated()), id: \.element.id) { index, song in
                                Button(action: {
                                    player.playQueue(album.song, startingAt: index)
                                }) {
                                    HStack {
                                        if let track = song.track {
                                            Text("\(track)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(width: 20, alignment: .leading)
                                        }

                                        VStack(alignment: .leading) {
                                            Text(song.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            if let duration = song.duration {
                                                Text(formatDuration(duration))
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        if player.currentSong?.id == song.id && player.isPlaying {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.caption2)
                                                .foregroundColor(.accentColor)
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
        .navigationTitle("Album")
        .onAppear {
            loadAlbum()
        }
    }

    private func loadAlbum() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedAlbum = try await NavidromeAPI.shared.getAlbum(id: albumId)
                await MainActor.run {
                    self.album = fetchedAlbum
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

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
