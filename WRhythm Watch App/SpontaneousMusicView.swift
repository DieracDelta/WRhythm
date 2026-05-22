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
        WRhythmScreen {
#if os(iOS)
            PhoneDetailHeader()
                .padding(.top, WRhythmSpacing.xxl)
                .padding(.bottom, WRhythmSpacing.md)
#endif

            WRhythmFeatureHeader(
                title: "Spontaneous Music",
                subtitle: offlineMode ? "Shuffle downloaded songs" : "Shuffle all songs",
                systemImage: "shuffle",
                tint: WRhythmTheme.spontaneous
            )

            WRhythmCard(style: .glass) {
                VStack(spacing: WRhythmSpacing.md) {
                    Button(action: shuffleAll) {
                        Label("Shuffle All", systemImage: "shuffle.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WRhythmTheme.spontaneous)
                    .controlSize(.large)
                    .disabled(isLoading)

                    if isLoading {
                        HStack(spacing: WRhythmSpacing.xs) {
                            ProgressView()
                            Text("Finding music")
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !errorMessage.isEmpty {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundColor(WRhythmTheme.danger)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            WRhythmCard {
                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    HStack(spacing: WRhythmSpacing.xs) {
                        Image(systemName: "shuffle.circle.fill")
                            .foregroundColor(WRhythmTheme.spontaneous)
                        Text(offlineMode ? "Offline Mode" : "Online Mode")
                            .font(WRhythmTypography.sectionLabel)
                    }

                    if offlineMode {
                        Text("Shuffles from \(downloadManager.getTotalDownloaded()) downloaded songs")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Fetches random songs from your entire library")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
#if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
#else
        .navigationTitle("Spontaneous")
#endif
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
