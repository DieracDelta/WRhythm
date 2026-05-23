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
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("\(selectedCount)")
                                .font(.title3)
                                .fontWeight(.semibold)
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
                            .font(.caption2)
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
                                .font(.caption)
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
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(sourceSong, count: selectedCount)
                print("📻 ID3 similar songs returned \(similarSongs.count) songs")

                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: selectedCount)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    isProcessing = false
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found to download for radio")
                    } else {
                        // Filter out the source song if it appears in results
                        let filteredSongs = similarSongs.filter { $0.id != sourceSong.id }

                        // Build queue with source song first, then similar songs
                        var queue = [sourceSong]
                        queue.append(contentsOf: filteredSongs)

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
