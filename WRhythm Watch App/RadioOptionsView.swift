//
//  RadioOptionsView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/24/25.
//

import SwiftUI

struct RadioOptionsView: View {
    let sourceSong: Song
    let sourceTitle: String  // e.g., "Song Title", "Album Name", "Artist Name"
    let sourceType: RadioSourceType

    @AppStorage("radioDownloadCount") private var radioDownloadCount = 25
    @State private var selectedCount: Int = 25
    @State private var isProcessing = false
    @Environment(\.dismiss) private var dismiss

    enum RadioSourceType {
        case song
        case album
        case artist
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WRhythmVisual.sectionSpacing) {
                WRhythmFeatureHeader(
                    title: "Playlist Gen Options",
                    subtitle: sourceTitle,
                    systemImage: "music.note.list",
                    tint: .pink,
                    coverArtId: sourceSong.coverArt
                )

                WRhythmCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Number of Songs")
                            .font(WRhythmTypography.rowSubtitle)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("\(selectedCount)")
                                .font(WRhythmTypography.numericValue)
                                .monospacedDigit()
                                .frame(width: 50, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { Double(selectedCount) },
                                    set: { selectedCount = Int($0) }
                                ),
                                in: 10...500,
                                step: 10
                            )
                        }

                        Text("Similar songs to include in Playlist Gen")
                            .font(WRhythmTypography.metadata)
                            .foregroundColor(.secondary)
                    }
                }

                WRhythmCard {
                    VStack(spacing: 12) {
                    Button(action: {
                        playRadio()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Playlist Gen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)

                    Button(action: {
                        downloadRadio()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download Playlist Gen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                    }
                }

                if isProcessing {
                    WRhythmCard {
                        HStack(spacing: WRhythmSpacing.xs) {
                            ProgressView()
                            Text("Preparing playlist")
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Playlist Gen")
        .wrhythmPageBackground(coverArtId: sourceSong.coverArt)
        .platformNavigationBarTitleDisplayModeInline()
        .onAppear {
            selectedCount = radioDownloadCount
        }
    }

    private func playRadio() {
        isProcessing = true
        AudioPlayer.shared.startPlaylistGeneration(for: sourceSong, count: selectedCount)
        isProcessing = false
        dismissAfterStateUpdates()
    }

    private func downloadRadio() {
        isProcessing = true
        Task {
            do {
                print("📻 Downloading radio for: \(sourceTitle) (count: \(selectedCount))")
                let similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(sourceSong, count: selectedCount)
                print("📻 ID3 similar songs returned \(similarSongs.count) songs")

                let primaryQueue = PlaylistGenerationPolicy.queue(
                    sourceSong: sourceSong,
                    primarySongs: similarSongs,
                    fallbackSongs: [],
                    requestedCount: selectedCount
                )
                let fallbackSongs: [Song]
                if PlaylistGenerationPolicy.needsFallback(currentCount: primaryQueue.count, requestedCount: selectedCount) {
                    print("📻 Topping up radio with random songs")
                    fallbackSongs = try await NavidromeAPI.shared.getRandomSongs(size: selectedCount)
                    print("📻 getRandomSongs returned \(fallbackSongs.count) songs")
                } else {
                    fallbackSongs = []
                }
                let queue = PlaylistGenerationPolicy.queue(
                    sourceSong: sourceSong,
                    primarySongs: similarSongs,
                    fallbackSongs: fallbackSongs,
                    requestedCount: selectedCount
                )

                await MainActor.run {
                    isProcessing = false
                    if queue.count <= 1 {
                        print("⚠️ No songs found to download for radio")
                    } else {
                        print("✅ Downloading radio: \(queue.count) songs")

                        // Download all songs in the radio queue
                        for radioSong in queue {
                            DownloadManager.shared.downloadSong(radioSong)
                        }

                        // Save radio playlist metadata
                        DownloadManager.shared.saveRadioPlaylist(sourceSong: sourceSong, songs: queue)
                    }
                    dismissAfterStateUpdates()
                }
            } catch {
                print("❌ Failed to download radio: \(error)")
                await MainActor.run {
                    isProcessing = false
                    dismissAfterStateUpdates()
                }
            }
        }
    }

    private func dismissAfterStateUpdates() {
        Task { @MainActor in
            await Task.yield()
            dismiss()
        }
    }
}
