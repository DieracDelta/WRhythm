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
                        ForEach(Array(downloadManager.activeDownloads.keys), id: \.self) { songId in
                            VStack(spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading) {
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

                                    let progress = downloadManager.downloadProgress(songId)
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }

                                ProgressView(value: downloadManager.downloadProgress(songId))
                                    .progressViewStyle(.linear)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Active Downloads")
    }

    private func findSongInfo(_ songId: String) -> Song? {
        // Try to find song info from already downloaded songs
        if let downloaded = downloadManager.downloadedSongs[songId] {
            return Song(
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
        return nil
    }
}
