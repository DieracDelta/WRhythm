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
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                    Text("Radio Options")
                        .font(.headline)
                    Text(sourceTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                Divider()

                // Song count selector
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

                    Text("Similar songs to include in radio")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        playRadio()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Play Radio")
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
                            Text("Download Radio")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                }

                if isProcessing {
                    ProgressView()
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Radio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedCount = radioDownloadCount
        }
    }

    private func playRadio() {
        isProcessing = true
        Task {
            do {
                print("🎵 Starting radio for: \(sourceTitle) (count: \(selectedCount))")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs(id: sourceSong.id, count: selectedCount)
                print("📻 getSimilarSongs returned \(similarSongs.count) songs")

                // Fallback 1: Try artist-based radio if no results
                if similarSongs.isEmpty, let artistId = sourceSong.artistId {
                    print("📻 Falling back to artist radio for artist ID: \(artistId)")
                    similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: selectedCount)
                    print("📻 getSimilarSongs2 returned \(similarSongs.count) songs")
                }

                // Fallback 2: Try random songs if still empty
                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: selectedCount)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    isProcessing = false
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found even with fallbacks, playing original song")
                        AudioPlayer.shared.playSong(sourceSong)
                    } else {
                        // Filter out the source song if it appears in results
                        let filteredSongs = similarSongs.filter { $0.id != sourceSong.id }

                        // Build queue with source song first, then similar songs
                        var queue = [sourceSong]
                        queue.append(contentsOf: filteredSongs)

                        print("✅ Radio queue ready: 1 source song + \(filteredSongs.count) similar songs = \(queue.count) total")
                        AudioPlayer.shared.playQueue(queue, startingAt: 0)
                        print("📻 Queue after playQueue: \(AudioPlayer.shared.queue.count) songs")
                    }
                    dismiss()
                }
            } catch {
                print("❌ Failed to start radio: \(error)")
                await MainActor.run {
                    isProcessing = false
                    AudioPlayer.shared.playSong(sourceSong)
                    dismiss()
                }
            }
        }
    }

    private func downloadRadio() {
        isProcessing = true
        Task {
            do {
                print("📻 Downloading radio for: \(sourceTitle) (count: \(selectedCount))")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs(id: sourceSong.id, count: selectedCount)
                print("📻 getSimilarSongs returned \(similarSongs.count) songs")

                // Fallback 1: Try artist-based radio if no results
                if similarSongs.isEmpty, let artistId = sourceSong.artistId {
                    print("📻 Falling back to artist radio for artist ID: \(artistId)")
                    similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: selectedCount)
                    print("📻 getSimilarSongs2 returned \(similarSongs.count) songs")
                }

                // Fallback 2: Try random songs if still empty
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
                    dismiss()
                }
            } catch {
                print("❌ Failed to download radio: \(error)")
                await MainActor.run {
                    isProcessing = false
                    dismiss()
                }
            }
        }
    }
}
