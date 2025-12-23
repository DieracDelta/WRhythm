//
//  DownloadManager.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import Combine

struct DownloadedSong: Codable {
    let songId: String
    let title: String
    let artist: String?
    let album: String?
    let coverArt: String?
    let filePath: String
    let downloadedAt: Date
    let fileSize: Int64
}

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    @Published var downloadedSongs: [String: DownloadedSong] = [:]
    @Published var activeDownloads: [String: Double] = [:] // songId -> progress

    private let fileManager = FileManager.default
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskToSongId: [URLSessionDownloadTask: String] = [:]
    private var songMetadata: [String: Song] = [:]
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var downloadsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var metadataURL: URL {
        documentsDirectory.appendingPathComponent("downloads.json")
    }

    override init() {
        super.init()
        loadMetadata()
    }

    // MARK: - Metadata

    private func loadMetadata() {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            print("📥 No download metadata found")
            return
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            let downloaded = try JSONDecoder().decode([String: DownloadedSong].self, from: data)
            self.downloadedSongs = downloaded
            print("📥 Loaded \(downloaded.count) downloaded songs")
        } catch {
            print("❌ Failed to load download metadata: \(error)")
        }
    }

    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(downloadedSongs)
            try data.write(to: metadataURL)
            print("💾 Saved download metadata")
        } catch {
            print("❌ Failed to save download metadata: \(error)")
        }
    }

    // MARK: - Download Status

    func isDownloaded(_ songId: String) -> Bool {
        guard let downloaded = downloadedSongs[songId] else { return false }
        return fileManager.fileExists(atPath: downloadsDirectory.appendingPathComponent(downloaded.filePath).path)
    }

    func isDownloading(_ songId: String) -> Bool {
        return activeDownloads[songId] != nil
    }

    func downloadProgress(_ songId: String) -> Double {
        return activeDownloads[songId] ?? 0
    }

    func getLocalURL(_ songId: String) -> URL? {
        guard let downloaded = downloadedSongs[songId] else { return nil }
        let url = downloadsDirectory.appendingPathComponent(downloaded.filePath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Download Song

    func downloadSong(_ song: Song) {
        guard !isDownloaded(song.id) && !isDownloading(song.id) else {
            print("⏭️ Song already downloaded or downloading: \(song.title)")
            return
        }

        guard let streamURL = NavidromeAPI.shared.getStreamURL(id: song.id) else {
            print("❌ Failed to get stream URL for: \(song.title)")
            return
        }

        print("📥 Starting download: \(song.title)")

        let task = downloadSession.downloadTask(with: streamURL)

        activeDownloads[song.id] = 0
        downloadTasks[song.id] = task
        taskToSongId[task] = song.id
        songMetadata[song.id] = song
        task.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let songId = taskToSongId[downloadTask] else { return }

        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0

        DispatchQueue.main.async {
            self.activeDownloads[songId] = progress
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let songId = taskToSongId[downloadTask],
              let song = songMetadata[songId] else {
            print("❌ No song info for completed download")
            return
        }

        let filename = "\(song.id).\(song.suffix ?? "mp3")"
        let destinationURL = downloadsDirectory.appendingPathComponent(filename)

        do {
            // Remove existing file if present
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: location, to: destinationURL)

            // Get file size
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            // Save metadata
            let downloadedSong = DownloadedSong(
                songId: song.id,
                title: song.title,
                artist: song.artist,
                album: song.album,
                coverArt: song.coverArt,
                filePath: filename,
                downloadedAt: Date(),
                fileSize: fileSize
            )

            DispatchQueue.main.async {
                self.downloadedSongs[song.id] = downloadedSong
                self.activeDownloads.removeValue(forKey: song.id)
                self.downloadTasks.removeValue(forKey: song.id)
                self.taskToSongId.removeValue(forKey: downloadTask)
                self.songMetadata.removeValue(forKey: song.id)
                self.saveMetadata()
                print("✅ Downloaded: \(song.title) (\(self.formatBytes(fileSize)))")
            }
        } catch {
            print("❌ Failed to save downloaded file: \(error)")
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: song.id)
                self.downloadTasks.removeValue(forKey: song.id)
                self.taskToSongId.removeValue(forKey: downloadTask)
                self.songMetadata.removeValue(forKey: song.id)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let songId = taskToSongId[downloadTask] else {
            return
        }

        if let error = error {
            print("❌ Download failed for song \(songId): \(error)")
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: songId)
                self.downloadTasks.removeValue(forKey: songId)
                self.taskToSongId.removeValue(forKey: downloadTask)
                self.songMetadata.removeValue(forKey: songId)
            }
        }
    }

    // MARK: - Download Collections

    func downloadAlbum(_ album: Album) {
        print("📥 Downloading album: \(album.name)")
        for song in album.song {
            downloadSong(song)
        }
    }

    func downloadPlaylist(_ playlist: Playlist) {
        print("📥 Downloading playlist: \(playlist.name)")
        guard let songs = playlist.entry else { return }
        for song in songs {
            downloadSong(song)
        }
    }

    func downloadArtist(_ artist: ArtistWithAlbums) async {
        print("📥 Downloading artist: \(artist.name)")
        for albumSummary in artist.album {
            do {
                let album = try await NavidromeAPI.shared.getAlbum(id: albumSummary.id)
                await MainActor.run {
                    downloadAlbum(album)
                }
            } catch {
                print("❌ Failed to fetch album \(albumSummary.name): \(error)")
            }
        }
    }

    // MARK: - Delete

    func deleteSong(_ songId: String) {
        guard let downloaded = downloadedSongs[songId] else { return }

        let fileURL = downloadsDirectory.appendingPathComponent(downloaded.filePath)

        do {
            try fileManager.removeItem(at: fileURL)
            downloadedSongs.removeValue(forKey: songId)
            saveMetadata()
            print("🗑️ Deleted: \(downloaded.title)")
        } catch {
            print("❌ Failed to delete file: \(error)")
        }
    }

    func deleteAlbum(_ album: Album) {
        for song in album.song {
            deleteSong(song.id)
        }
    }

    func deletePlaylist(_ playlist: Playlist) {
        guard let songs = playlist.entry else { return }
        for song in songs {
            deleteSong(song.id)
        }
    }

    func deleteAll() {
        for songId in downloadedSongs.keys {
            deleteSong(songId)
        }
    }

    // MARK: - Statistics

    func getTotalDownloaded() -> Int {
        return downloadedSongs.count
    }

    func getTotalSize() -> Int64 {
        return downloadedSongs.values.reduce(0) { $0 + $1.fileSize }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
