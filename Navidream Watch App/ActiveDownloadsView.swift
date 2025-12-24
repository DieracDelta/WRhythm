//
//  ActiveDownloadsView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ActiveDownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if downloadManager.activeDownloads.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Active Downloads")
                            .font(.headline)
                        Text("Downloads will appear here while in progress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(spacing: 4) {
                        Text("\(downloadManager.activeDownloads.count) downloading")
                            .font(.headline)
                    }
                    .padding(.vertical, 8)

                    Divider()

                    VStack(spacing: 12) {
                        // Active downloads
                        ForEach(Array(downloadManager.activeDownloads.keys), id: \.self) { songId in
                            VStack(spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if let song = findSongInfo(songId) {
                                            Text(song.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            if let artist = song.artist {
                                                Text(artist)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        } else {
                                            Text("Downloading...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    HStack(spacing: 8) {
                                        let progress = downloadManager.downloadProgress(songId)
                                        Text("\(Int(progress * 100))%")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .monospacedDigit()

                                        Button(action: {
                                            downloadManager.retryDownload(songId)
                                        }) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            downloadManager.cancelDownload(songId)
                                        }) {
                                            Image(systemName: "xmark")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.red)
                                    }
                                }

                                ProgressView(value: downloadManager.downloadProgress(songId))
                                    .progressViewStyle(.linear)
                            }
                            .padding(.horizontal)
                        }

                        // Queued downloads
                        if !downloadManager.downloadQueue.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Queued (\(downloadManager.downloadQueue.count))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)

                                ForEach(Array(downloadManager.downloadQueue.prefix(20)), id: \.id) { song in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(song.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            if let artist = song.artist {
                                                Text(artist)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        Spacer()

                                        HStack(spacing: 8) {
                                            Image(systemName: "clock")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            Button(action: {
                                                downloadManager.cancelDownload(song.id)
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.horizontal)
                                    .opacity(0.6)
                                }

                                if downloadManager.downloadQueue.count > 20 {
                                    Text("+ \(downloadManager.downloadQueue.count - 20) more...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Active Downloads")
    }

    private func findSongInfo(_ songId: String) -> Song? {
        // Get song metadata for active downloads
        return downloadManager.songMetadata[songId]
    }
}
