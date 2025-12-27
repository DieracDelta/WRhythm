//
//  SpontaneousMusicView.swift
//  WRhythm Watch App
//
//  Created by Claude on 12/24/25.
//

import SwiftUI

struct SpontaneousMusicView: View {
    @AppStorage("offlineMode") private var offlineMode = false
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var isLoading = false
    @State private var errorMessage = ""

    private var player: AudioPlayer { AudioPlayer.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)

                    Text("Spontaneous Music")
                        .font(.headline)

                    Text(offlineMode ? "Shuffle downloaded songs" : "Shuffle all songs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                Divider()

                // Shuffle Button
                Button(action: {
                    shuffleAll()
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "shuffle.circle.fill")
                            .font(.system(size: 50))
                        Text("Shuffle All")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .padding()
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                // Info section
                VStack(alignment: .leading, spacing: 8) {
                    if offlineMode {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Offline Mode")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }

                        Text("Shuffles from \(downloadManager.getTotalDownloaded()) downloaded songs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Online Mode")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }

                        Text("Fetches random songs from your entire library")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Spontaneous")
    }

    private func shuffleAll() {
        if offlineMode {
            shuffleOffline()
        } else {
            shuffleOnline()
        }
    }

    private func shuffleOffline() {
        // Get all downloaded songs and shuffle them
        let downloadedSongs = Array(downloadManager.downloadedSongs.values)

        guard !downloadedSongs.isEmpty else {
            errorMessage = "No downloaded songs available"
            return
        }

        errorMessage = ""

        // Convert to Song objects
        let songs = downloadedSongs.map { downloaded in
            Song(
                id: downloaded.songId,
                title: downloaded.title,
                album: downloaded.album,
                albumId: nil,
                artist: downloaded.artist,
                artistId: nil,
                track: nil,
                year: nil,
                genre: nil,
                coverArt: downloaded.coverArt,
                size: Int(downloaded.fileSize),
                contentType: nil,
                suffix: nil,
                duration: nil,
                bitRate: nil,
                path: downloaded.filePath
            )
        }

        // Shuffle and play
        player.playQueueShuffled(songs)
        print("🎵 Started spontaneous music with \(songs.count) downloaded songs")
    }

    private func shuffleOnline() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                // Fetch random songs from API
                let songs = try await NavidromeAPI.shared.getRandomSongs(size: 100)

                await MainActor.run {
                    isLoading = false

                    guard !songs.isEmpty else {
                        errorMessage = "No songs available"
                        return
                    }

                    // Shuffle and play
                    player.playQueueShuffled(songs)
                    print("🎵 Started spontaneous music with \(songs.count) random songs")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to load songs: \(error.localizedDescription)"
                    print("❌ Error loading random songs: \(error)")
                }
            }
        }
    }
}

#Preview {
    SpontaneousMusicView()
}
