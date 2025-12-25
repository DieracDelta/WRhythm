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

struct CachedPlaylist: Codable {
    let id: String
    let name: String
    let songCount: Int
    let coverArt: String?
    let songIds: [String]  // Store song IDs so we can filter in offline mode
    let cachedAt: Date
}

struct RadioPlaylist: Codable, Identifiable {
    let id: String  // ID of the source song
    let sourceSongTitle: String
    let sourceSongArtist: String?
    let coverArt: String?
    let songIds: [String]
    let createdAt: Date
}

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()

    @Published var downloadedSongs: [String: DownloadedSong] = [:]
    @Published var cachedPlaylists: [CachedPlaylist] = []
    @Published var radioPlaylists: [RadioPlaylist] = []
    @Published var starredSongIds: Set<String> = []
    @Published var pendingStarChanges: Set<String> = []  // Songs to star on server
    @Published var pendingUnstarChanges: Set<String> = []  // Songs to unstar on server
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
    private(set) var songMetadata: [String: Song] = [:]  // Expose for reading
    @Published var downloadQueue: [Song] = []  // Expose queue for UI

    // Throttling for progress updates
    private var lastProgressUpdate: Date = .distantPast
    private var pendingProgressUpdates: [String: Double] = [:]

    // Track total bytes for downloads
    private var downloadTotalBytes: [String: Int64] = [:] // songId -> total expected bytes

    // Track cumulative bytes for current download session
    @Published var sessionBytesDownloaded: Int64 = 0
    @Published var sessionBytesTotal: Int64 = 0
    @Published var sessionCompletedCount: Int = 0
    @Published var sessionTotalCount: Int = 0

    // Pause state
    @Published var isPaused: Bool = false
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.navidream.downloads")
        config.isDiscretionary = false // Download immediately, don't wait for optimal conditions
        config.sessionSendsLaunchEvents = true // Launch app when downloads complete in background
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

    private var playlistsMetadataURL: URL {
        documentsDirectory.appendingPathComponent("playlists.json")
    }

    private var radioPlaylistsURL: URL {
        documentsDirectory.appendingPathComponent("radio_playlists.json")
    }

    private var starredSongsURL: URL {
        documentsDirectory.appendingPathComponent("starred_songs.json")
    }

    private var pendingStarChangesURL: URL {
        documentsDirectory.appendingPathComponent("pending_star_changes.json")
    }

    private var songMetadataURL: URL {
        documentsDirectory.appendingPathComponent("song_metadata.json")
    }

    private var pendingUnstarChangesURL: URL {
        documentsDirectory.appendingPathComponent("pending_unstar_changes.json")
    }

    private var incompleteDownloadsURL: URL {
        documentsDirectory.appendingPathComponent("incomplete_downloads.json")
    }

    override init() {
        super.init()
        loadMetadata()
        loadSongMetadata()
        loadPlaylistsMetadata()
        loadRadioPlaylists()
        loadStarredSongs()
        loadPendingChanges()
        loadIncompleteDownloads()

        // Log when app becomes active to see download state
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSExtensionHostDidBecomeActive,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            print("🔔 [\(timestamp)] App became active")
            print("📊 [\(timestamp)] Download state - Active: \(self.activeDownloads.count), Queue: \(self.downloadQueue.count)")
            if !self.activeDownloads.isEmpty {
                for (songId, progress) in self.activeDownloads {
                    let title = self.songMetadata[songId]?.title ?? "Unknown"
                    print("   - \(title): \(Int(progress * 100))%")
                }
            }
        }
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

    private func loadSongMetadata() {
        guard fileManager.fileExists(atPath: songMetadataURL.path) else {
            print("📥 No song metadata found")
            return
        }

        do {
            let data = try Data(contentsOf: songMetadataURL)
            let metadata = try JSONDecoder().decode([String: Song].self, from: data)
            self.songMetadata = metadata
            print("📥 Loaded \(metadata.count) song metadata entries")
        } catch {
            print("❌ Failed to load song metadata: \(error)")
        }
    }

    private func saveSongMetadata() {
        do {
            let data = try JSONEncoder().encode(songMetadata)
            try data.write(to: songMetadataURL)
            print("💾 Saved song metadata (\(songMetadata.count) entries)")
        } catch {
            print("❌ Failed to save song metadata: \(error)")
        }
    }

    private func loadPlaylistsMetadata() {
        guard fileManager.fileExists(atPath: playlistsMetadataURL.path) else {
            print("📥 No playlist metadata found")
            return
        }

        do {
            let data = try Data(contentsOf: playlistsMetadataURL)
            let playlists = try JSONDecoder().decode([CachedPlaylist].self, from: data)
            self.cachedPlaylists = playlists
            print("📥 Loaded \(playlists.count) cached playlists")
        } catch {
            print("❌ Failed to load playlist metadata: \(error)")
        }
    }

    private func savePlaylistsMetadata() {
        do {
            let data = try JSONEncoder().encode(cachedPlaylists)
            try data.write(to: playlistsMetadataURL)
            print("💾 Saved playlist metadata")
        } catch {
            print("❌ Failed to save playlist metadata: \(error)")
        }
    }

    private func loadRadioPlaylists() {
        guard fileManager.fileExists(atPath: radioPlaylistsURL.path) else {
            print("📥 No radio playlists found")
            return
        }

        do {
            let data = try Data(contentsOf: radioPlaylistsURL)
            let radios = try JSONDecoder().decode([RadioPlaylist].self, from: data)
            self.radioPlaylists = radios
            print("📥 Loaded \(radios.count) radio playlists")
        } catch {
            print("❌ Failed to load radio playlists: \(error)")
        }
    }

    private func saveRadioPlaylists() {
        do {
            let data = try JSONEncoder().encode(radioPlaylists)
            try data.write(to: radioPlaylistsURL)
            print("💾 Saved radio playlists metadata")
        } catch {
            print("❌ Failed to save radio playlists metadata: \(error)")
        }
    }

    private func loadStarredSongs() {
        guard fileManager.fileExists(atPath: starredSongsURL.path) else {
            print("📥 No starred songs found")
            return
        }

        do {
            let data = try Data(contentsOf: starredSongsURL)
            let songIds = try JSONDecoder().decode([String].self, from: data)
            self.starredSongIds = Set(songIds)
            print("📥 Loaded \(songIds.count) starred songs")
        } catch {
            print("❌ Failed to load starred songs: \(error)")
        }
    }

    private func saveStarredSongs() {
        do {
            let data = try JSONEncoder().encode(Array(starredSongIds))
            try data.write(to: starredSongsURL)
            print("💾 Saved \(starredSongIds.count) starred songs")
        } catch {
            print("❌ Failed to save starred songs: \(error)")
        }
    }

    func cacheStarredSongs(_ songIds: Set<String>) {
        self.starredSongIds = songIds
        saveStarredSongs()
    }

    private func loadPendingChanges() {
        // Load pending star changes
        if fileManager.fileExists(atPath: pendingStarChangesURL.path) {
            do {
                let data = try Data(contentsOf: pendingStarChangesURL)
                let songIds = try JSONDecoder().decode([String].self, from: data)
                self.pendingStarChanges = Set(songIds)
                print("📥 Loaded \(songIds.count) pending star changes")
            } catch {
                print("❌ Failed to load pending star changes: \(error)")
            }
        }

        // Load pending unstar changes
        if fileManager.fileExists(atPath: pendingUnstarChangesURL.path) {
            do {
                let data = try Data(contentsOf: pendingUnstarChangesURL)
                let songIds = try JSONDecoder().decode([String].self, from: data)
                self.pendingUnstarChanges = Set(songIds)
                print("📥 Loaded \(songIds.count) pending unstar changes")
            } catch {
                print("❌ Failed to load pending unstar changes: \(error)")
            }
        }
    }

    private func savePendingChanges() {
        // Save pending star changes
        do {
            let data = try JSONEncoder().encode(Array(pendingStarChanges))
            try data.write(to: pendingStarChangesURL)
            print("💾 Saved \(pendingStarChanges.count) pending star changes")
        } catch {
            print("❌ Failed to save pending star changes: \(error)")
        }

        // Save pending unstar changes
        do {
            let data = try JSONEncoder().encode(Array(pendingUnstarChanges))
            try data.write(to: pendingUnstarChangesURL)
            print("💾 Saved \(pendingUnstarChanges.count) pending unstar changes")
        } catch {
            print("❌ Failed to save pending unstar changes: \(error)")
        }
    }

    private func loadIncompleteDownloads() {
        guard fileManager.fileExists(atPath: incompleteDownloadsURL.path) else {
            print("📥 No incomplete downloads found")
            return
        }

        do {
            let data = try Data(contentsOf: incompleteDownloadsURL)
            let songIds = try JSONDecoder().decode([String].self, from: data)
            print("📥 Loaded \(songIds.count) incomplete downloads")

            // Re-queue songs that have metadata but weren't completed
            for songId in songIds {
                if let song = songMetadata[songId], !isDownloaded(songId) {
                    downloadQueue.append(song)
                    print("📥 Re-queued incomplete download: \(song.title)")
                }
            }

            // Start processing if we have items
            if !downloadQueue.isEmpty {
                sessionTotalCount = downloadQueue.count
                processQueue()
            }
        } catch {
            print("❌ Failed to load incomplete downloads: \(error)")
        }
    }

    private func saveIncompleteDownloads() {
        // Collect all song IDs that are in queue or actively downloading
        var incompleteIds: [String] = []
        incompleteIds.append(contentsOf: downloadQueue.map { $0.id })
        incompleteIds.append(contentsOf: activeDownloads.keys)

        do {
            let data = try JSONEncoder().encode(incompleteIds)
            try data.write(to: incompleteDownloadsURL)
            print("💾 Saved \(incompleteIds.count) incomplete downloads")
        } catch {
            print("❌ Failed to save incomplete downloads: \(error)")
        }
    }

    private func clearIncompleteDownloads() {
        do {
            if fileManager.fileExists(atPath: incompleteDownloadsURL.path) {
                try fileManager.removeItem(at: incompleteDownloadsURL)
                print("🗑️ Cleared incomplete downloads")
            }
        } catch {
            print("❌ Failed to clear incomplete downloads: \(error)")
        }
    }

    // Star a song locally, and track for sync if offline
    func starSong(_ songId: String, isOffline: Bool) {
        starredSongIds.insert(songId)
        saveStarredSongs()

        if isOffline {
            pendingStarChanges.insert(songId)
            pendingUnstarChanges.remove(songId)  // Cancel any pending unstar
            savePendingChanges()
            print("⭐ Queued star for sync: \(songId)")
        }
    }

    // Unstar a song locally, and track for sync if offline
    func unstarSong(_ songId: String, isOffline: Bool) {
        starredSongIds.remove(songId)
        saveStarredSongs()

        if isOffline {
            pendingUnstarChanges.insert(songId)
            pendingStarChanges.remove(songId)  // Cancel any pending star
            savePendingChanges()
            print("⭐ Queued unstar for sync: \(songId)")
        }
    }

    // Sync pending changes to server
    func syncPendingStarChanges() async throws {
        print("🔄 Syncing pending star changes...")

        var errors: [Error] = []

        // Process pending stars
        for songId in pendingStarChanges {
            do {
                try await NavidromeAPI.shared.star(songId: songId)
                print("✅ Synced star: \(songId)")
            } catch {
                print("❌ Failed to sync star for \(songId): \(error)")
                errors.append(error)
            }
        }

        // Process pending unstars
        for songId in pendingUnstarChanges {
            do {
                try await NavidromeAPI.shared.unstar(songId: songId)
                print("✅ Synced unstar: \(songId)")
            } catch {
                print("❌ Failed to sync unstar for \(songId): \(error)")
                errors.append(error)
            }
        }

        // If all succeeded, clear pending changes
        if errors.isEmpty {
            pendingStarChanges.removeAll()
            pendingUnstarChanges.removeAll()
            savePendingChanges()
            print("✅ All pending star changes synced")
        } else {
            throw errors.first!
        }
    }

    func saveRadioPlaylist(sourceSong: Song, songs: [Song]) {
        let radio = RadioPlaylist(
            id: sourceSong.id,
            sourceSongTitle: sourceSong.title,
            sourceSongArtist: sourceSong.artist,
            coverArt: sourceSong.coverArt,
            songIds: songs.map { $0.id },
            createdAt: Date()
        )

        // Replace existing radio with same source song or add new
        if let index = radioPlaylists.firstIndex(where: { $0.id == sourceSong.id }) {
            radioPlaylists[index] = radio
        } else {
            radioPlaylists.append(radio)
        }

        saveRadioPlaylists()
        print("💾 Saved radio playlist for: \(sourceSong.title)")
    }

    func deleteRadioPlaylist(_ radioId: String) {
        radioPlaylists.removeAll { $0.id == radioId }
        saveRadioPlaylists()
        print("🗑️ Deleted radio playlist: \(radioId)")
    }

    func cachePlaylists(_ playlists: [PlaylistSummary]) {
        self.cachedPlaylists = playlists.map { playlist in
            CachedPlaylist(
                id: playlist.id,
                name: playlist.name,
                songCount: playlist.songCount,
                coverArt: playlist.coverArt,
                songIds: [],  // Will be updated when playlist is loaded
                cachedAt: Date()
            )
        }
        savePlaylistsMetadata()
    }

    func cachePlaylistDetails(_ playlist: Playlist) {
        // Update or add full playlist details with song IDs
        if let index = cachedPlaylists.firstIndex(where: { $0.id == playlist.id }) {
            cachedPlaylists[index] = CachedPlaylist(
                id: playlist.id,
                name: playlist.name,
                songCount: playlist.songCount,
                coverArt: playlist.coverArt,
                songIds: playlist.entry?.map { $0.id } ?? [],
                cachedAt: Date()
            )
        } else {
            cachedPlaylists.append(CachedPlaylist(
                id: playlist.id,
                name: playlist.name,
                songCount: playlist.songCount,
                coverArt: playlist.coverArt,
                songIds: playlist.entry?.map { $0.id } ?? [],
                cachedAt: Date()
            ))
        }
        savePlaylistsMetadata()
    }

    // MARK: - Download Status

    func isDownloaded(_ songId: String) -> Bool {
        guard let downloaded = downloadedSongs[songId] else { return false }
        return fileManager.fileExists(atPath: downloadsDirectory.appendingPathComponent(downloaded.filePath).path)
    }

    func isDownloading(_ songId: String) -> Bool {
        // Check if actively downloading or queued
        return activeDownloads[songId] != nil || downloadQueue.contains(where: { $0.id == songId })
    }

    // MARK: - Download Control

    func pauseDownloads() {
        print("⏸️ Pausing all downloads")
        isPaused = true
        // Cancel all active download tasks
        for (_, task) in downloadTasks {
            task.cancel()
        }
        // Don't clear the queue - we'll resume from it
        saveIncompleteDownloads()
    }

    func resumeDownloads() {
        print("▶️ Resuming downloads")
        isPaused = false
        // Process queue will restart downloads
        processQueue()
    }

    func restartDownloads() {
        print("🔄 Restarting all downloads")
        isPaused = false

        // Cancel all active tasks
        for (_, task) in downloadTasks {
            task.cancel()
        }

        // Collect all incomplete song IDs
        var incompleteIds: Set<String> = []
        incompleteIds.formUnion(downloadQueue.map { $0.id })
        incompleteIds.formUnion(activeDownloads.keys)

        // Clear current state
        activeDownloads.removeAll()
        downloadTasks.removeAll()
        taskToSongId.removeAll()
        downloadBytesReceived.removeAll()
        downloadTotalBytes.removeAll()
        pendingProgressUpdates.removeAll()
        downloadQueue.removeAll()

        // Re-queue all incomplete downloads from metadata
        for songId in incompleteIds {
            if let song = songMetadata[songId], !isDownloaded(songId) {
                downloadQueue.append(song)
                print("🔄 Re-queued: \(song.title)")
            }
        }

        print("🔄 Restarting \(downloadQueue.count) downloads")
        saveIncompleteDownloads()
        processQueue()
    }

    func cancelAllDownloads() {
        print("❌ Cancelling all downloads")
        isPaused = false
        // Cancel all active tasks
        for (_, task) in downloadTasks {
            task.cancel()
        }
        // Clear everything
        downloadQueue.removeAll()
        activeDownloads.removeAll()
        downloadTasks.removeAll()
        taskToSongId.removeAll()
        // Only remove metadata for songs that aren't already downloaded
        let downloadedIds = Set(downloadedSongs.keys)
        songMetadata = songMetadata.filter { downloadedIds.contains($0.key) }
        saveSongMetadata()
        downloadBytesReceived.removeAll()
        downloadTotalBytes.removeAll()
        pendingProgressUpdates.removeAll()

        // Reset session counters
        sessionBytesDownloaded = 0
        sessionBytesTotal = 0
        sessionCompletedCount = 0
        sessionTotalCount = 0

        // Clear incomplete downloads since we cancelled everything
        clearIncompleteDownloads()
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
        saveIncompleteDownloads()
        processQueue()
    }

    private func processQueue() {
        // Don't process if paused
        guard !isPaused else {
            print("⏸️ Downloads are paused, not processing queue")
            return
        }

        // Start downloads up to the concurrent limit (999 = unlimited)
        let isUnlimited = maxConcurrentDownloads == 999

        while (isUnlimited || activeDownloads.count < maxConcurrentDownloads) && !downloadQueue.isEmpty {
            let song = downloadQueue.removeFirst()

            guard let streamURL = NavidromeAPI.shared.getStreamURL(id: song.id) else {
                print("❌ Failed to get stream URL for: \(song.title)")
                continue
            }

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let limitText = isUnlimited ? "∞" : "\(maxConcurrentDownloads)"
            print("📥 [\(timestamp)] Starting download (\(activeDownloads.count + 1)/\(limitText)): \(song.title)")

            let task = downloadSession.downloadTask(with: streamURL)

            activeDownloads[song.id] = 0
            downloadTasks[song.id] = task
            taskToSongId[task] = song.id
            songMetadata[song.id] = song
            task.resume()

            print("▶️ [\(timestamp)] Download task resumed for: \(song.title)")
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

        // Calculate progress
        let progress: Double
        let estimatedTotal: Int64

        if totalBytesExpectedToWrite > 0 {
            estimatedTotal = totalBytesExpectedToWrite
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

            // Log progress at 25%, 50%, 75%, 100% milestones
            let percentage = Int(progress * 100)
            if percentage % 25 == 0 && percentage > 0 {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                print("📊 [\(timestamp)] Progress \(percentage)% - \(song.title) - \(totalBytesWritten)/\(totalBytesExpectedToWrite) bytes")
            }
        } else {
            // No Content-Length (transcoding) - estimate based on song duration
            if let duration = song.duration, duration > 0 {
                estimatedTotal = Int64(duration) * 16000 // 16KB/s * duration in seconds
                progress = min(0.99, Double(totalBytesWritten) / Double(estimatedTotal))
            } else {
                // No duration either - just show indeterminate progress
                estimatedTotal = 5_000_000 // 5MB estimate
                progress = min(0.95, Double(totalBytesWritten) / Double(estimatedTotal))
            }
        }

        DispatchQueue.main.async {
            self.downloadBytesReceived[songId] = totalBytesWritten

            // Track total bytes for this download if we haven't yet
            if self.downloadTotalBytes[songId] == nil {
                self.downloadTotalBytes[songId] = estimatedTotal
                self.sessionBytesTotal += estimatedTotal
                self.sessionTotalCount += 1
            } else if self.downloadTotalBytes[songId] != estimatedTotal {
                // Update session total if estimate changed
                let oldTotal = self.downloadTotalBytes[songId] ?? 0
                self.sessionBytesTotal += (estimatedTotal - oldTotal)
                self.downloadTotalBytes[songId] = estimatedTotal
            }

            // Store pending update
            self.pendingProgressUpdates[songId] = progress

            // Throttle UI updates to once per second
            let now = Date()
            if now.timeIntervalSince(self.lastProgressUpdate) >= 1.0 {
                self.lastProgressUpdate = now

                // Apply all pending updates at once
                for (id, prog) in self.pendingProgressUpdates {
                    self.activeDownloads[id] = prog
                }
                self.pendingProgressUpdates.removeAll()

                // Log status every 10 seconds
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let activeCount = self.activeDownloads.count
                let queueCount = self.downloadQueue.count
                let completedCount = self.sessionCompletedCount

                // Only log every 10th update (every ~10 seconds)
                if Int(now.timeIntervalSince1970) % 10 == 0 {
                    print("📊 [\(timestamp)] Status - Completed: \(completedCount), Active: \(activeCount), Queue: \(queueCount)")
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
                // Apply any pending progress updates before removing
                if let pendingProgress = self.pendingProgressUpdates[song.id] {
                    self.activeDownloads[song.id] = pendingProgress
                    self.pendingProgressUpdates.removeValue(forKey: song.id)
                }

                // Add completed bytes and count to session totals
                self.sessionBytesDownloaded += fileSize
                self.sessionCompletedCount += 1

                self.downloadedSongs[song.id] = downloadedSong
                self.activeDownloads.removeValue(forKey: song.id)
                self.downloadBytesReceived.removeValue(forKey: song.id)
                self.downloadTotalBytes.removeValue(forKey: song.id)
                self.downloadTasks.removeValue(forKey: song.id)
                self.taskToSongId.removeValue(forKey: downloadTask)
                // Keep songMetadata for offline mode - don't remove it!
                // self.songMetadata.removeValue(forKey: song.id)
                self.saveMetadata()
                self.saveSongMetadata()

                let timestamp = ISO8601DateFormatter().string(from: Date())
                print("✅ [\(timestamp)] Downloaded: \(song.title) (\(self.formatBytes(fileSize)))")
                print("📊 [\(timestamp)] Active downloads: \(self.activeDownloads.count), Queue: \(self.downloadQueue.count)")

                // Reset session counters if all downloads are done
                if self.activeDownloads.isEmpty && self.downloadQueue.isEmpty {
                    print("🏁 [\(timestamp)] All downloads complete - resetting session counters")
                    self.sessionBytesDownloaded = 0
                    self.sessionBytesTotal = 0
                    self.sessionCompletedCount = 0
                    self.sessionTotalCount = 0
                    self.clearIncompleteDownloads()
                } else {
                    self.saveIncompleteDownloads()
                }

                // Process next item in queue
                self.processQueue()
            }
        } catch {
            print("❌ Failed to save downloaded file: \(error)")
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: song.id)
                self.downloadBytesReceived.removeValue(forKey: song.id)
                self.downloadTotalBytes.removeValue(forKey: song.id)
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
            if let error = error {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                print("❌ [\(timestamp)] Download task completed with error but no song mapping")
                print("   Error: \(error.localizedDescription)")
            }
            return
        }

        if let error = error {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let songTitle = self.songMetadata[songId]?.title ?? "Unknown"
            print("❌ [\(timestamp)] Download failed for: \(songTitle)")
            print("   Error: \(error.localizedDescription)")
            print("   Error code: \((error as NSError).code)")
            print("   Error domain: \((error as NSError).domain)")
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: songId)
                self.downloadBytesReceived.removeValue(forKey: songId)
                self.downloadTotalBytes.removeValue(forKey: songId)
                self.downloadTasks.removeValue(forKey: songId)
                self.taskToSongId.removeValue(forKey: downloadTask)
                self.songMetadata.removeValue(forKey: songId)

                print("📊 [\(timestamp)] After error - Active downloads: \(self.activeDownloads.count), Queue: \(self.downloadQueue.count)")

                // Process next item in queue on error
                self.processQueue()
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("🎉 [\(timestamp)] Background session finished all events")
        print("📊 [\(timestamp)] Active downloads: \(self.activeDownloads.count), Queue: \(self.downloadQueue.count)")
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

    // MARK: - Cancel & Retry

    func cancelDownload(_ songId: String) {
        // Cancel active download
        if let task = downloadTasks[songId] {
            task.cancel()
            print("🛑 Cancelled download for song: \(songId)")

            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: songId)
                self.downloadBytesReceived.removeValue(forKey: songId)
                self.downloadTasks.removeValue(forKey: songId)
                if let task = self.downloadTasks[songId] {
                    self.taskToSongId.removeValue(forKey: task)
                }
                self.songMetadata.removeValue(forKey: songId)

                // Process next in queue
                self.processQueue()
            }
            return
        }

        // Remove from queue
        if let index = downloadQueue.firstIndex(where: { $0.id == songId }) {
            let song = downloadQueue.remove(at: index)
            print("🛑 Removed from queue: \(song.title)")
        }
    }

    func retryDownload(_ songId: String) {
        // Get song metadata
        guard let song = songMetadata[songId] else {
            print("❌ No metadata found for retry: \(songId)")
            return
        }

        print("🔄 Retrying download: \(song.title)")

        // Cancel existing download if active
        if let task = downloadTasks[songId] {
            task.cancel()
            activeDownloads.removeValue(forKey: songId)
            downloadBytesReceived.removeValue(forKey: songId)
            downloadTasks.removeValue(forKey: songId)
            taskToSongId.removeValue(forKey: task)
        }

        // Re-add to queue
        downloadQueue.insert(song, at: 0) // Add to front of queue
        processQueue()
    }

    // MARK: - Delete

    func deleteSong(_ songId: String) {
        guard let downloaded = downloadedSongs[songId] else { return }

        let fileURL = downloadsDirectory.appendingPathComponent(downloaded.filePath)

        do {
            try fileManager.removeItem(at: fileURL)
            downloadedSongs.removeValue(forKey: songId)
            songMetadata.removeValue(forKey: songId)
            saveMetadata()
            saveSongMetadata()
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

    // MARK: - Offline Mode Filtering

    func hasDownloadedSongsForAlbum(_ albumId: String) -> Bool {
        return downloadedSongs.values.contains { $0.album == albumId }
    }

    func getDownloadedSongsForAlbum(_ albumId: String) -> [String] {
        return downloadedSongs.values.filter { $0.album == albumId }.map { $0.songId }
    }

    func getDownloadedAlbums() -> [(id: String, name: String, artist: String?, coverArt: String?)] {
        var albums: [String: (name: String, artist: String?, coverArt: String?)] = [:]

        // Use songMetadata to get full Song objects for downloaded songs
        for song in songMetadata.values where isDownloaded(song.id) {
            if let albumId = song.albumId {
                // Use first song's data for the album
                if albums[albumId] == nil {
                    albums[albumId] = (song.album ?? "Unknown Album", song.artist, song.coverArt)
                }
            }
        }

        return albums.map { (id: $0.key, name: $0.value.name, artist: $0.value.artist, coverArt: $0.value.coverArt) }
            .sorted { $0.name < $1.name }
    }

    func getDownloadedArtists() -> [(name: String, coverArt: String?)] {
        var artists: [String: String?] = [:] // artistName -> coverArt

        // Use songMetadata to get full Song objects for downloaded songs
        for song in songMetadata.values where isDownloaded(song.id) {
            if let artistName = song.artist {
                // Only set coverArt if we don't already have one for this artist
                if artists[artistName] == nil {
                    artists[artistName] = song.coverArt
                }
            }
        }

        return artists.map { (name: $0.key, coverArt: $0.value) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Statistics

    func getTotalDownloaded() -> Int {
        return downloadedSongs.count
    }

    func getTotalSize() -> Int64 {
        return downloadedSongs.values.reduce(0) { $0 + $1.fileSize }
    }

    func getActiveDownloadCount() -> Int {
        return activeDownloads.count
    }

    func getQueuedDownloadCount() -> Int {
        return downloadQueue.count
    }

    func getTotalPendingDownloads() -> Int {
        return activeDownloads.count + downloadQueue.count
    }

    func getAverageDownloadProgress() -> Double {
        guard !activeDownloads.isEmpty else { return 0 }
        let total = activeDownloads.values.reduce(0.0, +)
        return total / Double(activeDownloads.count)
    }

    func getTotalBytesToDownload() -> Int64 {
        // Return session total which includes both active and completed downloads
        return sessionBytesTotal
    }

    func getTotalBytesDownloaded() -> Int64 {
        // Session completed + currently downloading
        let activeBytes = downloadBytesReceived.values.reduce(0, +)
        return sessionBytesDownloaded + activeBytes
    }

    func getBytesRemaining() -> Int64 {
        let total = getTotalBytesToDownload()
        let downloaded = getTotalBytesDownloaded()
        return max(0, total - downloaded)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
