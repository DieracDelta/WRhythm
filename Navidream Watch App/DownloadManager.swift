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
    @Published var activeDownloads: [String: Double] = [:] // songId -> progress (0-1)
    @Published var downloadBytesReceived: [String: Int64] = [:] // songId -> bytes downloaded
    @Published var maxConcurrentDownloads: Int = UserDefaults.standard.integer(forKey: "maxConcurrentDownloads") == 0 ? 8 : UserDefaults.standard.integer(forKey: "maxConcurrentDownloads") {
        didSet {
            UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads")
            processQueue()
        }
    }

    private let fileManager = FileManager.default
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskToSongId: [URLSessionDownloadTask: String] = [:]
    private var songMetadata: [String: Song] = [:]
    private var downloadQueue: [Song] = []
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

        // Check if song is already in queue
        guard !downloadQueue.contains(where: { $0.id == song.id }) else {
            print("⏳ Song already queued: \(song.title)")
            return
        }

        downloadQueue.append(song)
        print("📋 Added to queue: \(song.title) (queue size: \(downloadQueue.count))")
        processQueue()
    }

    private func processQueue() {
        // Start downloads up to the concurrent limit
        while activeDownloads.count < maxConcurrentDownloads && !downloadQueue.isEmpty {
            let song = downloadQueue.removeFirst()

            guard let streamURL = NavidromeAPI.shared.getStreamURL(id: song.id) else {
                print("❌ Failed to get stream URL for: \(song.title)")
                continue
            }

            print("📥 Starting download (\(activeDownloads.count + 1)/\(maxConcurrentDownloads)): \(song.title)")

            let task = downloadSession.downloadTask(with: streamURL)

            activeDownloads[song.id] = 0
            downloadTasks[song.id] = task
            taskToSongId[task] = song.id
            songMetadata[song.id] = song
            task.resume()
        }

        if !downloadQueue.isEmpty {
            print("⏳ \(downloadQueue.count) songs waiting in queue")
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let songId = taskToSongId[downloadTask],
              let song = songMetadata[songId] else {
            return
        }

        DispatchQueue.main.async {
            self.downloadBytesReceived[songId] = totalBytesWritten

            // If server provides Content-Length, use it for accurate progress
            if totalBytesExpectedToWrite > 0 {
                let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                self.activeDownloads[songId] = progress
            } else {
                // No Content-Length (transcoding) - estimate based on song duration
                // Assume ~128kbps (16KB/s) for MP3 transcoding
                if let duration = song.duration, duration > 0 {
                    let estimatedSize = Int64(duration) * 16000 // 16KB/s * duration in seconds
                    let progress = min(0.99, Double(totalBytesWritten) / Double(estimatedSize))
                    self.activeDownloads[songId] = progress
                } else {
                    // No duration either - just show indeterminate progress
                    // Fake progress that never reaches 100%
                    let fakProgress = min(0.95, Double(totalBytesWritten) / 5_000_000.0)
                    self.activeDownloads[songId] = fakProgress
                }
            }
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
                self.downloadBytesReceived.removeValue(forKey: song.id)
                self.downloadTasks.removeValue(forKey: song.id)
                self.taskToSongId.removeValue(forKey: downloadTask)
                self.songMetadata.removeValue(forKey: song.id)
                self.saveMetadata()
                print("✅ Downloaded: \(song.title) (\(self.formatBytes(fileSize)))")

                // Process next item in queue
                self.processQueue()
            }
        } catch {
            print("❌ Failed to save downloaded file: \(error)")
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: song.id)
                self.downloadBytesReceived.removeValue(forKey: song.id)
                self.downloadTasks.removeValue(forKey: song.id)
                self.taskToSongId.removeValue(forKey: downloadTask)
                self.songMetadata.removeValue(forKey: song.id)

                // Process next item in queue even on error
                self.processQueue()
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
                self.downloadBytesReceived.removeValue(forKey: songId)
                self.downloadTasks.removeValue(forKey: songId)
                self.taskToSongId.removeValue(forKey: downloadTask)
                self.songMetadata.removeValue(forKey: songId)

                // Process next item in queue on error
                self.processQueue()
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
