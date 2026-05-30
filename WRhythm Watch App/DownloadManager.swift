//
//  DownloadManager.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import Combine

private struct DownloadTaskHandle: @unchecked Sendable {
    let task: URLSessionTask
}

nonisolated private struct DownloadCompletionContext: Sendable {
    let songId: String
    let fileName: String
    let destinationURL: URL
    let downloadedBitRate: Int
}

nonisolated private struct CompletedDownloadFile: Sendable {
    let songId: String
    let fileName: String
    let fileSize: Int64
    let downloadedBitRate: Int
}

nonisolated private final class DownloadCompletionContextStore: @unchecked Sendable {
    private let lock = NSLock()
    private var contextsByTaskIdentifier: [Int: DownloadCompletionContext] = [:]

    nonisolated func set(_ context: DownloadCompletionContext, for taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        contextsByTaskIdentifier[taskIdentifier] = context
    }

    nonisolated func removeContext(for taskIdentifier: Int) -> DownloadCompletionContext? {
        lock.lock()
        defer { lock.unlock() }
        return contextsByTaskIdentifier.removeValue(forKey: taskIdentifier)
    }

    nonisolated func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        contextsByTaskIdentifier.removeAll()
    }
}

final class SerialFileWriteQueue: @unchecked Sendable {
    private let queue: DispatchQueue

    nonisolated init(label: String) {
        self.queue = DispatchQueue(label: label, qos: .utility)
    }

    nonisolated func write(_ data: Data, to url: URL, label: String) {
        queue.async {
            do {
                try data.write(to: url)
                print("💾 \(label)")
            } catch {
                print("❌ Failed to write \(label): \(error)")
            }
        }
    }

    nonisolated func writeImmediately(_ data: Data, to url: URL, label: String) {
        queue.sync {
            do {
                try data.write(to: url, options: .atomic)
                print("💾 \(label)")
            } catch {
                print("❌ Failed to write \(label): \(error)")
            }
        }
    }

    nonisolated func removeItem(at url: URL, label: String) {
        queue.async {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    print("🗑️ \(label)")
                }
            } catch {
                print("❌ Failed to remove \(label): \(error)")
            }
        }
    }

    nonisolated func removeItemImmediately(at url: URL, label: String) {
        queue.sync {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    print("🗑️ \(label)")
                }
            } catch {
                print("❌ Failed to remove \(label): \(error)")
            }
        }
    }

    nonisolated func waitForIdle() {
        queue.sync {}
    }
}

// MARK: - Audio Quality Settings

enum AudioQuality: Int, CaseIterable, Codable, Sendable {
    case original = 0
    case low = 64
    case medium = 128
    case high = 192
    case max = 320

    nonisolated var label: String {
        switch self {
        case .original: return "Original"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    nonisolated var description: String {
        switch self {
        case .original: return "Original file - largest downloads"
        case .low: return "64 kbps MP3 - Smallest files"
        case .medium: return "128 kbps MP3 - Balanced"
        case .high: return "192 kbps MP3 - Better quality"
        case .max: return "320 kbps MP3 - Best lossy quality"
        }
    }

    nonisolated var shortDescription: String {
        switch self {
        case .original: return "Original"
        default: return "\(rawValue) kbps"
        }
    }

    nonisolated var streamFormat: String? {
        self == .original ? nil : "mp3"
    }

    nonisolated var maxBitRate: Int? {
        self == .original ? nil : rawValue
    }

    nonisolated var downloadedBitRate: Int {
        rawValue
    }

    nonisolated static func savedQuality(from storedValue: Int?) -> AudioQuality {
        storedValue.flatMap { AudioQuality(rawValue: $0) } ?? .medium
    }

    nonisolated func localFileExtension(for song: Song) -> String {
        if let streamFormat {
            return streamFormat
        }

        guard let suffix = song.suffix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !suffix.isEmpty,
            suffix.allSatisfy({ $0.isLetter || $0.isNumber })
        else {
            return "audio"
        }

        return suffix
    }
}

enum StreamingQuality: Int, CaseIterable, Codable, Sendable {
    case original = 0
    case low = 64
    case medium = 128
    case high = 192
    case max = 320

    nonisolated static var platformDefault: StreamingQuality {
#if os(watchOS)
        return .medium
#else
        return .original
#endif
    }

    static var current: StreamingQuality {
        let savedValue = UserDefaults.standard.object(forKey: "streamingQuality") as? Int
        return savedValue.flatMap { StreamingQuality(rawValue: $0) } ?? platformDefault
    }

    nonisolated var label: String {
        switch self {
        case .original: return "Original"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }

    nonisolated var description: String {
        switch self {
        case .original: return "Original stream - FLAC/lossless when the server and device support it"
        case .low: return "64 kbps MP3"
        case .medium: return "128 kbps MP3"
        case .high: return "192 kbps MP3"
        case .max: return "320 kbps MP3"
        }
    }

    nonisolated var maxBitRate: Int? {
        self == .original ? nil : rawValue
    }
}

// MARK: - Migration State (for crash recovery during codec change)

nonisolated struct MigrationState: Codable, Sendable {
    let inProgress: Bool
    let targetBitRate: Int
    let songsToRedownload: [String]  // song IDs
    let startedAt: Date
}

struct DownloadedSong: Codable, Sendable {
    let songId: String
    let title: String
    let artist: String?
    let album: String?
    let coverArt: String?
    let filePath: String
    let downloadedAt: Date
    let fileSize: Int64
    let downloadedBitRate: Int

    enum CodingKeys: String, CodingKey {
        case songId
        case title
        case artist
        case album
        case coverArt
        case filePath
        case downloadedAt
        case fileSize
        case downloadedBitRate
    }

    init(songId: String, title: String, artist: String?, album: String?, coverArt: String?, filePath: String, downloadedAt: Date, fileSize: Int64, downloadedBitRate: Int) {
        self.songId = songId
        self.title = title
        self.artist = artist
        self.album = album
        self.coverArt = coverArt
        self.filePath = filePath
        self.downloadedAt = downloadedAt
        self.fileSize = fileSize
        self.downloadedBitRate = downloadedBitRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.songId = try container.decode(String.self, forKey: .songId)
        self.title = try container.decode(String.self, forKey: .title)
        self.artist = try container.decodeIfPresent(String.self, forKey: .artist)
        self.album = try container.decodeIfPresent(String.self, forKey: .album)
        self.coverArt = try container.decodeIfPresent(String.self, forKey: .coverArt)
        self.filePath = try container.decode(String.self, forKey: .filePath)
        self.downloadedAt = try container.decode(Date.self, forKey: .downloadedAt)
        self.fileSize = try container.decode(Int64.self, forKey: .fileSize)
        self.downloadedBitRate = try container.decodeIfPresent(Int.self, forKey: .downloadedBitRate) ?? AudioQuality.original.downloadedBitRate
    }
}

struct FailedDownload: Identifiable, Sendable {
    let songId: String
    let title: String
    let artist: String?
    let album: String?
    let coverArt: String?
    let errorDescription: String
    let failedAt: Date

    var id: String { songId }

    init(song: Song, errorDescription: String, failedAt: Date = Date()) {
        self.songId = song.id
        self.title = song.title
        self.artist = song.artist
        self.album = song.album
        self.coverArt = song.coverArt
        self.errorDescription = errorDescription
        self.failedAt = failedAt
    }
}

struct CachedPlaylist: Codable, Sendable {
    let id: String
    let name: String
    let songCount: Int
    let coverArt: String?
    let songIds: [String]  // Store song IDs so we can filter in offline mode
    let cachedAt: Date
}

struct RadioPlaylist: Codable, Identifiable, Sendable {
    let id: String  // ID of the source song
    let sourceSongTitle: String
    let sourceSongArtist: String?
    let coverArt: String?
    let songIds: [String]
    let createdAt: Date
}

@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    private nonisolated static let delegateEventSubmitter = SyncDelegateEventSubmitter(label: "WRhythm.DownloadDelegateEvents")
    private nonisolated static let metadataWriteQueue = SerialFileWriteQueue(label: "WRhythm.DownloadMetadataWrites")
    private nonisolated static let completionContextStore = DownloadCompletionContextStore()

    @Published var downloadedSongs: [String: DownloadedSong] = [:]
    @Published var cachedPlaylists: [CachedPlaylist] = []
    @Published var radioPlaylists: [RadioPlaylist] = []
    @Published var starredSongIds: Set<String> = []
    @Published var pendingStarChanges: Set<String> = []  // Songs to star on server
    @Published var pendingUnstarChanges: Set<String> = []  // Songs to unstar on server
    @Published var activeDownloads: [String: Double] = [:] // songId -> progress (0-1)
    @Published var failedDownloads: [String: FailedDownload] = [:]
    @Published var downloadNotice: DownloadUserNotice?
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

    // Audio quality settings
    @Published var audioQuality: AudioQuality = {
        let savedValue = UserDefaults.standard.object(forKey: "audioQuality") as? Int
        return AudioQuality.savedQuality(from: savedValue)
    }()

    // Quality change state (for prompting user)
    @Published var showQualityChangePrompt: Bool = false
    @Published var pendingQualityChange: AudioQuality? = nil
    @Published var isExecutingQualityChange: Bool = false

    // Low-priority background queue for downloads to prevent UI freezing
    private lazy var downloadQueue_background: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.wrhythm.downloads.delegate"
        queue.qualityOfService = .utility  // Lower priority than UI
        queue.maxConcurrentOperationCount = 1  // Serial queue to prevent overwhelming
        return queue
    }()

    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.wrhythm.downloads")
        config.isDiscretionary = false // Download immediately, don't wait for optimal conditions
        config.sessionSendsLaunchEvents = true // Launch app when downloads complete in background
        return URLSession(configuration: config, delegate: self, delegateQueue: downloadQueue_background)
    }()

    private var storageDirectory: URL {
        #if os(macOS)
        let url = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WRhythm", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
        #else
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }

    private var downloadsDirectory: URL {
        let url = storageDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var metadataURL: URL {
        storageDirectory.appendingPathComponent("downloads.json")
    }

    private var playlistsMetadataURL: URL {
        storageDirectory.appendingPathComponent("playlists.json")
    }

    private var radioPlaylistsURL: URL {
        storageDirectory.appendingPathComponent("radio_playlists.json")
    }

    private var starredSongsURL: URL {
        storageDirectory.appendingPathComponent("starred_songs.json")
    }

    private var pendingStarChangesURL: URL {
        storageDirectory.appendingPathComponent("pending_star_changes.json")
    }

    private var songMetadataURL: URL {
        storageDirectory.appendingPathComponent("song_metadata.json")
    }

    private var pendingUnstarChangesURL: URL {
        storageDirectory.appendingPathComponent("pending_unstar_changes.json")
    }

    private var incompleteDownloadsURL: URL {
        storageDirectory.appendingPathComponent("incomplete_downloads.json")
    }

    private var migrationStateURL: URL {
        storageDirectory.appendingPathComponent("migration_state.json")
    }

    override init() {
        super.init()
        loadMetadata()
        loadSongMetadata()
        reconcileDownloadedFilesFromDisk()
        loadPlaylistsMetadata()
        loadRadioPlaylists()
        loadStarredSongs()
        loadPendingChanges()
        loadIncompleteDownloads()
        checkAndResumeMigration()

        // Log when app becomes active to see download state
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSExtensionHostDidBecomeActive"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logDownloadStateForActiveApp()
            }
        }
    }

    nonisolated private static func enqueueDelegateEvent(_ operation: @escaping @MainActor @Sendable () -> Void) {
        delegateEventSubmitter.enqueue(operation)
    }

    private func logDownloadStateForActiveApp() {
        let timestamp = Date.now.formatted(.iso8601)
        print("🔔 [\(timestamp)] App became active")
        print("📊 [\(timestamp)] Download state - Active: \(activeDownloads.count), Queue: \(downloadQueue.count)")
        if !activeDownloads.isEmpty {
            for (songId, progress) in activeDownloads {
                let title = songMetadata[songId]?.title ?? "Unknown"
                print("   - \(title): \(Int(progress * 100))%")
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
        let songsToSave = downloadedSongs
        let url = metadataURL
        do {
            let data = try JSONEncoder().encode(songsToSave)
            Self.metadataWriteQueue.writeImmediately(data, to: url, label: "Saved download metadata")
        } catch {
            print("❌ Failed to encode download metadata: \(error)")
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
        let metadataToSave = songMetadata
        let url = songMetadataURL
        do {
            let data = try JSONEncoder().encode(metadataToSave)
            Self.metadataWriteQueue.writeImmediately(data, to: url, label: "Saved song metadata (\(metadataToSave.count) entries)")
        } catch {
            print("❌ Failed to encode song metadata: \(error)")
        }
    }

    private func reconcileDownloadedFilesFromDisk() {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: downloadsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            let candidates = try fileURLs.compactMap { fileURL -> DownloadedFileCandidate? in
                let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
                guard values.isDirectory != true else { return nil }
                return DownloadedFileCandidate(
                    fileName: fileURL.lastPathComponent,
                    fileSize: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate
                )
            }

            let reconciled = DownloadedFileReconciliationPolicy.reconciledDownloads(
                existingDownloads: downloadedSongs,
                songMetadata: songMetadata,
                files: candidates,
                now: Date()
            )

            guard reconciled.count != downloadedSongs.count else { return }
            downloadedSongs = reconciled
            saveMetadata()
            print("📥 Reconciled \(reconciled.count) downloaded songs from disk")
        } catch {
            print("❌ Failed to reconcile downloaded files: \(error)")
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
            let completedSongIds = Set(downloadedSongs.keys.filter { isDownloaded($0) })
            let songs = try DownloadRequestPersistencePolicy.decodeIncompleteDownloads(
                from: data,
                songMetadata: songMetadata,
                downloadedSongIds: completedSongIds
            )
            print("📥 Loaded \(songs.count) incomplete downloads")

            for song in songs where !isDownloaded(song.id) {
                songMetadata[song.id] = song
                if !downloadQueue.contains(where: { $0.id == song.id }) {
                    downloadQueue.append(song)
                    print("📥 Re-queued incomplete download: \(song.title)")
                }
            }

            // Start processing if we have items
            if !downloadQueue.isEmpty {
                sessionTotalCount = downloadQueue.count
                saveSongMetadata()
                saveIncompleteDownloads()
                processQueue()
            }
        } catch {
            print("❌ Failed to load incomplete downloads: \(error)")
        }
    }

    private func saveIncompleteDownloads() {
        let activeSongs = Dictionary(uniqueKeysWithValues: activeDownloads.keys.compactMap { songId in
            songMetadata[songId].map { (songId, $0) }
        })

        let url = incompleteDownloadsURL
        do {
            let data = try DownloadRequestPersistencePolicy.encodeIncompleteDownloads(
                queuedSongs: downloadQueue,
                activeSongs: activeSongs
            )
            let incompleteCount = downloadQueue.count + activeSongs.count
            Self.metadataWriteQueue.writeImmediately(data, to: url, label: "Saved \(incompleteCount) incomplete downloads")
        } catch {
            print("❌ Failed to encode incomplete downloads: \(error)")
        }
    }

    private func clearIncompleteDownloads() {
        Self.metadataWriteQueue.removeItemImmediately(at: incompleteDownloadsURL, label: "Cleared incomplete downloads")
    }

    // MARK: - Migration State (Codec Change Recovery)

    private func loadMigrationState() -> MigrationState? {
        guard fileManager.fileExists(atPath: migrationStateURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: migrationStateURL)
            return try JSONDecoder().decode(MigrationState.self, from: data)
        } catch {
            print("❌ Failed to load migration state: \(error)")
            return nil
        }
    }

    private func saveMigrationState(_ state: MigrationState) {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: migrationStateURL)
            print("💾 Saved migration state")
        } catch {
            print("❌ Failed to save migration state: \(error)")
        }
    }

    private func clearMigrationState() {
        do {
            if fileManager.fileExists(atPath: migrationStateURL.path) {
                try fileManager.removeItem(at: migrationStateURL)
                print("🗑️ Cleared migration state")
            }
        } catch {
            print("❌ Failed to clear migration state: \(error)")
        }
    }

    private func checkAndResumeMigration() {
        guard let state = loadMigrationState(), state.inProgress else {
            return
        }

        print("🔄 Found incomplete migration from \(state.startedAt)")
        print("   Target quality: \(AudioQuality(rawValue: state.targetBitRate)?.shortDescription ?? "\(state.targetBitRate)kbps")")
        print("   Songs to redownload: \(state.songsToRedownload.count)")

        // Resume the migration
        Task {
            await resumeMigration(state)
        }
    }

    private func resumeMigration(_ state: MigrationState) async {
        guard let targetQuality = AudioQuality(rawValue: state.targetBitRate) else {
            print("❌ Invalid target bitrate in migration state: \(state.targetBitRate)")
            clearMigrationState()
            return
        }

        print("🔄 Resuming migration to \(targetQuality.label) quality...")

        await MainActor.run {
            isExecutingQualityChange = true
            audioQuality = targetQuality
            UserDefaults.standard.set(targetQuality.rawValue, forKey: "audioQuality")
        }

        // Get song objects from metadata for songs that still need re-download
        let songsToQueue = state.songsToRedownload.compactMap { songMetadata[$0] }
            .filter { !isDownloaded($0.id) }

        if songsToQueue.isEmpty {
            print("✅ Migration already complete, clearing state")
            clearMigrationState()
            await MainActor.run {
                isExecutingQualityChange = false
            }
            return
        }

        await MainActor.run {
            // Queue the songs for download
            for song in songsToQueue {
                if !downloadQueue.contains(where: { $0.id == song.id }) && !isDownloading(song.id) {
                    downloadQueue.append(song)
                    sessionTotalCount += 1
                }
            }
            saveIncompleteDownloads()
            processQueue()
            isExecutingQualityChange = false
        }

        print("📥 Re-queued \(songsToQueue.count) songs for download")
        clearMigrationState()
    }

    // MARK: - Quality Change Handling

    func requestQualityChange(to newQuality: AudioQuality) {
        // Don't change if same quality
        guard newQuality != audioQuality else {
            print("ℹ️ Quality unchanged, no action needed")
            return
        }

        // If no downloads exist, just change the setting
        if downloadedSongs.isEmpty && activeDownloads.isEmpty && downloadQueue.isEmpty {
            audioQuality = newQuality
            UserDefaults.standard.set(newQuality.rawValue, forKey: "audioQuality")
            print("✅ Changed audio quality to \(newQuality.label) (no downloads to migrate)")
            return
        }

        // Otherwise, prompt for confirmation
        pendingQualityChange = newQuality
        showQualityChangePrompt = true
        print("⚠️ Quality change requested: \(audioQuality.label) -> \(newQuality.label)")
        print("   \(downloadedSongs.count) downloaded songs will need re-download")
    }

    func cancelQualityChange() {
        pendingQualityChange = nil
        showQualityChangePrompt = false
        print("❌ Quality change cancelled")
    }

    func executeQualityChange() async {
        guard let newQuality = pendingQualityChange else {
            print("❌ No pending quality change to execute")
            return
        }

        print("🔄 Executing quality change: \(audioQuality.label) -> \(newQuality.label)")

        await MainActor.run {
            isExecutingQualityChange = true
            showQualityChangePrompt = false
        }

        // 1. Collect song IDs to re-download BEFORE any deletion
        let songsToRedownload = Array(downloadedSongs.keys)
        print("📋 Songs to re-download: \(songsToRedownload.count)")

        // 2. Save migration state for crash recovery
        let migrationState = MigrationState(
            inProgress: true,
            targetBitRate: newQuality.rawValue,
            songsToRedownload: songsToRedownload,
            startedAt: Date()
        )
        saveMigrationState(migrationState)

        // 3. Cancel all active downloads
        await MainActor.run {
            cancelAllDownloads()
        }

        // 4. Get song metadata BEFORE deleting (so we can re-queue)
        let songObjectsToRedownload = songsToRedownload.compactMap { songMetadata[$0] }

        // 5. Delete all downloaded files
        await MainActor.run {
            deleteAll()
        }

        // 6. Update quality setting
        await MainActor.run {
            audioQuality = newQuality
            UserDefaults.standard.set(newQuality.rawValue, forKey: "audioQuality")
        }

        // 7. Re-queue all songs for download
        await MainActor.run {
            sessionTotalCount = songObjectsToRedownload.count
            for song in songObjectsToRedownload {
                // Re-add metadata since deleteAll() removed it
                songMetadata[song.id] = song
                downloadQueue.append(song)
            }
            saveSongMetadata()
            saveIncompleteDownloads()
            processQueue()
        }

        // 8. Clear migration state and pending change
        clearMigrationState()
        await MainActor.run {
            pendingQualityChange = nil
            isExecutingQualityChange = false
        }

        print("✅ Quality change complete, re-downloading \(songObjectsToRedownload.count) songs at \(newQuality.label)")
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

    func hasDownloadedFile(_ downloadedSong: DownloadedSong) -> Bool {
        fileManager.fileExists(atPath: downloadsDirectory.appendingPathComponent(downloadedSong.filePath).path)
    }

    func isDownloading(_ songId: String) -> Bool {
        // Check if actively downloading or queued
        return activeDownloads[songId] != nil || downloadQueue.contains(where: { $0.id == songId })
    }

    func downloadStatus(for songId: String) -> DownloadRowStatus {
        DownloadStatusPresentationPolicy.status(
            songId: songId,
            isDownloaded: isDownloaded(songId),
            activeProgress: activeDownloads[songId],
            queuedSongIds: Set(downloadQueue.map(\.id))
        )
    }

    func clearDownloadNotice(_ noticeID: UUID? = nil) {
        guard let noticeID else {
            downloadNotice = nil
            return
        }

        if downloadNotice?.id == noticeID {
            downloadNotice = nil
        }
    }

    private func showDownloadNotice(_ kind: DownloadNoticeKind) {
        downloadNotice = DownloadUserNotice(message: DownloadNoticePresentationPolicy.message(for: kind))
    }

    // MARK: - Download Control

    func pauseDownloads() {
        print("⏸️ Pausing all downloads")
        isPaused = true

        // Re-queue active downloads to the front of the queue before cancelling
        for (songId, _) in activeDownloads {
            if let song = songMetadata[songId] {
                // Add to front of queue if not already there
                if !downloadQueue.contains(where: { $0.id == songId }) {
                    downloadQueue.insert(song, at: 0)
                    print("📋 Re-queued active download: \(song.title)")
                }
            }
        }

        // Cancel all active download tasks
        for (_, task) in downloadTasks {
            task.cancel()
        }

        // Clear active downloads state (but keep metadata and queue)
        activeDownloads.removeAll()
        downloadTasks.removeAll()
        taskToSongId.removeAll()
        Self.completionContextStore.removeAll()
        downloadBytesReceived.removeAll()
        downloadTotalBytes.removeAll()

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
        Self.completionContextStore.removeAll()
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
        failedDownloads.removeAll()
        downloadTasks.removeAll()
        taskToSongId.removeAll()
        Self.completionContextStore.removeAll()
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

        failedDownloads.removeValue(forKey: song.id)

        // Check if song is already in queue
        guard !downloadQueue.contains(where: { $0.id == song.id }) else {
            print("⏳ Song already queued: \(song.title)")
            return
        }

        downloadQueue.append(song)
        songMetadata[song.id] = song

        // Update session total count to include this new song
        sessionTotalCount += 1

        print("📋 Added to queue: \(song.title) (queue size: \(downloadQueue.count))")
        saveSongMetadata()
        saveIncompleteDownloads()
        showDownloadNotice(.song(title: song.title))
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

            // Use selected audio quality for transcoding
            let quality = audioQuality
            guard let streamURL = NavidromeAPI.shared.getStreamURL(
                id: song.id,
                format: quality.streamFormat,
                maxBitRate: quality.maxBitRate
            ) else {
                print("❌ Failed to get stream URL for: \(song.title)")
                songMetadata[song.id] = song
                failedDownloads[song.id] = FailedDownload(song: song, errorDescription: "Could not build stream URL")
                saveSongMetadata()
                saveIncompleteDownloads()
                continue
            }

            let timestamp = Date.now.formatted(.iso8601)
            let limitText = isUnlimited ? "∞" : "\(maxConcurrentDownloads)"
            print("📥 [\(timestamp)] Starting download (\(activeDownloads.count + 1)/\(limitText)): \(song.title) @ \(audioQuality.shortDescription)")

            let task = downloadSession.downloadTask(with: streamURL)
            task.taskDescription = song.id
            let filename = "\(song.id).\(quality.localFileExtension(for: song))"
            let destinationURL = downloadsDirectory.appendingPathComponent(filename)
            Self.completionContextStore.set(
                DownloadCompletionContext(
                    songId: song.id,
                    fileName: filename,
                    destinationURL: destinationURL,
                    downloadedBitRate: quality.downloadedBitRate
                ),
                for: task.taskIdentifier
            )

            activeDownloads[song.id] = 0
            downloadTasks[song.id] = task
            taskToSongId[task] = song.id
            songMetadata[song.id] = song
            saveSongMetadata()
            saveIncompleteDownloads()
            task.resume()

            print("▶️ [\(timestamp)] Download task resumed for: \(song.title)")
        }

        if !downloadQueue.isEmpty {
            print("⏳ \(downloadQueue.count) songs waiting in queue")
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskHandle = DownloadTaskHandle(task: downloadTask)
        Self.enqueueDelegateEvent {
            guard let downloadTask = taskHandle.task as? URLSessionDownloadTask else { return }
            DownloadManager.shared.handleDownloadProgress(downloadTask: downloadTask, totalBytesWritten: totalBytesWritten, totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        }
    }

    private func handleDownloadProgress(downloadTask: URLSessionDownloadTask, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let songId = songId(for: downloadTask),
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
                let timestamp = Date.now.formatted(.iso8601)
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

        downloadBytesReceived[songId] = totalBytesWritten

        // Track total bytes for this download if we haven't yet
        if downloadTotalBytes[songId] == nil {
            downloadTotalBytes[songId] = estimatedTotal
            sessionBytesTotal += estimatedTotal
        } else if downloadTotalBytes[songId] != estimatedTotal {
            // Update session total if estimate changed
            let oldTotal = downloadTotalBytes[songId] ?? 0
            sessionBytesTotal += (estimatedTotal - oldTotal)
            downloadTotalBytes[songId] = estimatedTotal
        }

        // Store pending update
        pendingProgressUpdates[songId] = progress

        // Throttle UI updates to once every 2 seconds to reduce UI load
        let now = Date()
        if now.timeIntervalSince(lastProgressUpdate) >= 2.0 {
            lastProgressUpdate = now

            // Apply all pending updates at once
            for (id, prog) in pendingProgressUpdates {
                activeDownloads[id] = prog
            }
            pendingProgressUpdates.removeAll()

            // Log status every 10 seconds
            let timestamp = Date.now.formatted(.iso8601)
            let activeCount = activeDownloads.count
            let queueCount = downloadQueue.count
            let completedCount = sessionCompletedCount

            // Only log every 10th update (every ~10 seconds)
            if Int(now.timeIntervalSince1970) % 10 == 0 {
                print("📊 [\(timestamp)] Status - Completed: \(completedCount), Active: \(activeCount), Queue: \(queueCount)")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let taskHandle = DownloadTaskHandle(task: downloadTask)
        let taskIdentifier = downloadTask.taskIdentifier
        guard let context = Self.completionContextStore.removeContext(for: taskIdentifier) else {
            Self.enqueueDelegateEvent {
                guard let downloadTask = taskHandle.task as? URLSessionDownloadTask else { return }
                DownloadManager.shared.handleDownloadFinishedMoveFailed(
                    downloadTask: downloadTask,
                    error: CocoaError(.fileNoSuchFile)
                )
            }
            return
        }

        let movedFile: CompletedDownloadFile
        do {
            let fileSize = try CompletedDownloadFileMovePolicy.moveTemporaryDownload(
                from: location,
                to: context.destinationURL
            )
            movedFile = CompletedDownloadFile(
                songId: context.songId,
                fileName: context.fileName,
                fileSize: fileSize,
                downloadedBitRate: context.downloadedBitRate
            )
        } catch {
            Self.enqueueDelegateEvent {
                guard let downloadTask = taskHandle.task as? URLSessionDownloadTask else { return }
                DownloadManager.shared.handleDownloadFinishedMoveFailed(downloadTask: downloadTask, error: error)
            }
            return
        }

        Self.enqueueDelegateEvent {
            guard let downloadTask = taskHandle.task as? URLSessionDownloadTask else { return }
            DownloadManager.shared.handleDownloadFinished(downloadTask: downloadTask, movedFile: movedFile)
        }
    }

    private func handleDownloadFinished(downloadTask: URLSessionDownloadTask, movedFile: CompletedDownloadFile) {
        let resolvedSongId = songId(for: downloadTask) ?? movedFile.songId
        guard let song = songMetadata[resolvedSongId] else {
            print("❌ No song info for completed download")
            return
        }

        let downloadedSong = DownloadedSong(
            songId: song.id,
            title: song.title,
            artist: song.artist,
            album: song.album,
            coverArt: song.coverArt,
            filePath: movedFile.fileName,
            downloadedAt: Date(),
            fileSize: movedFile.fileSize,
            downloadedBitRate: movedFile.downloadedBitRate
        )

        // Apply any pending progress updates before removing
        if let pendingProgress = pendingProgressUpdates[song.id] {
            activeDownloads[song.id] = pendingProgress
            pendingProgressUpdates.removeValue(forKey: song.id)
        }

        // Add completed bytes and count to session totals
        sessionBytesDownloaded += movedFile.fileSize
        sessionCompletedCount += 1

        downloadedSongs[song.id] = downloadedSong
        activeDownloads.removeValue(forKey: song.id)
        failedDownloads.removeValue(forKey: song.id)
        downloadBytesReceived.removeValue(forKey: song.id)
        downloadTotalBytes.removeValue(forKey: song.id)
        downloadTasks.removeValue(forKey: song.id)
        taskToSongId.removeValue(forKey: downloadTask)
        // Keep songMetadata for offline mode - don't remove it!
        // songMetadata.removeValue(forKey: song.id)
        saveMetadata()
        saveSongMetadata()
        Task {
            await StoredAlbumArtworkCache.persistIfEnabled(coverArtId: song.coverArt)
        }

        let timestamp = Date.now.formatted(.iso8601)
        print("✅ [\(timestamp)] Downloaded: \(song.title) (\(formatBytes(movedFile.fileSize)))")
        print("📊 [\(timestamp)] Active downloads: \(activeDownloads.count), Queue: \(downloadQueue.count)")

        // Reset session counters if all downloads are done
        if activeDownloads.isEmpty && downloadQueue.isEmpty {
            print("🏁 [\(timestamp)] All downloads complete - resetting session counters")
            sessionBytesDownloaded = 0
            sessionBytesTotal = 0
            sessionCompletedCount = 0
            sessionTotalCount = 0
            clearIncompleteDownloads()
        } else {
            saveIncompleteDownloads()
        }

        // Process next item in queue
        processQueue()
    }

    private func handleDownloadFinishedMoveFailed(downloadTask: URLSessionDownloadTask, error: Error) {
        guard let songId = songId(for: downloadTask),
              let song = songMetadata[songId] else {
            print("❌ Failed to save downloaded file, and no song info was available: \(error)")
            return
        }

        print("❌ Failed to save downloaded file: \(error)")
        failedDownloads[song.id] = FailedDownload(song: song, errorDescription: error.localizedDescription)
        activeDownloads.removeValue(forKey: song.id)
        downloadBytesReceived.removeValue(forKey: song.id)
        downloadTotalBytes.removeValue(forKey: song.id)
        downloadTasks.removeValue(forKey: song.id)
        taskToSongId.removeValue(forKey: downloadTask)
        saveIncompleteDownloads()

        // Process next item in queue even on error
        processQueue()
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let taskHandle = DownloadTaskHandle(task: task)
        Self.enqueueDelegateEvent {
            DownloadManager.shared.handleDownloadCompleted(task: taskHandle.task, error: error)
        }
    }

    private func handleDownloadCompleted(task: URLSessionTask, error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let songId = songId(for: downloadTask) else {
            if let error = error {
                let timestamp = Date.now.formatted(.iso8601)
                print("❌ [\(timestamp)] Download task completed with error but no song mapping")
                print("   Error: \(error.localizedDescription)")
            }
            return
        }

        if let error = error {
            let timestamp = Date.now.formatted(.iso8601)
            let songTitle = self.songMetadata[songId]?.title ?? "Unknown"
            let nsError = error as NSError

            // Check if this is a cancellation error (user paused or cancelled)
            let isCancellation = nsError.code == NSURLErrorCancelled

            print("❌ [\(timestamp)] Download failed for: \(songTitle)")
            print("   Error: \(error.localizedDescription)")
            print("   Error code: \(nsError.code)")
            print("   Error domain: \(nsError.domain)")
            print("   Is cancellation: \(isCancellation)")

            activeDownloads.removeValue(forKey: songId)
            downloadBytesReceived.removeValue(forKey: songId)
            downloadTotalBytes.removeValue(forKey: songId)
            downloadTasks.removeValue(forKey: songId)
            taskToSongId.removeValue(forKey: downloadTask)
            _ = Self.completionContextStore.removeContext(for: downloadTask.taskIdentifier)

            // Only remove metadata if it's not a cancellation error
            // For cancellations (pause/cancel), we keep metadata so retry works
            if !isCancellation {
                if let song = songMetadata[songId] {
                    failedDownloads[songId] = FailedDownload(song: song, errorDescription: error.localizedDescription)
                } else {
                    songMetadata.removeValue(forKey: songId)
                }
            }

            print("📊 [\(timestamp)] After error - Active downloads: \(activeDownloads.count), Queue: \(downloadQueue.count)")

            // Only process next item if not paused
            if !isPaused {
                saveIncompleteDownloads()
                processQueue()
            } else {
                saveIncompleteDownloads()
            }
        }
    }

    private func songId(for downloadTask: URLSessionDownloadTask) -> String? {
        DownloadTaskIdentityPolicy.songId(
            for: downloadTask,
            mappedSongId: taskToSongId[downloadTask],
            taskDescription: downloadTask.taskDescription
        )
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let timestamp = Date.now.formatted(.iso8601)
            print("🎉 [\(timestamp)] Background session finished all events")
            print("📊 [\(timestamp)] Active downloads: \(self.activeDownloads.count), Queue: \(self.downloadQueue.count)")
        }
    }

    // MARK: - Download Collections

    func downloadAlbum(_ album: Album) {
        print("📥 Downloading album: \(album.name)")
        var queuedCount = 0
        // Add all songs to the queue first, then process
        for song in album.song {
            guard !isDownloaded(song.id) && !isDownloading(song.id) else {
                print("⏭️ Song already downloaded or downloading: \(song.title)")
                continue
            }

            guard !downloadQueue.contains(where: { $0.id == song.id }) else {
                print("⏳ Song already queued: \(song.title)")
                continue
            }

            downloadQueue.append(song)
            songMetadata[song.id] = song
            sessionTotalCount += 1
            queuedCount += 1
            print("📋 Added to queue: \(song.title)")
        }
        if queuedCount > 0 {
            saveSongMetadata()
            showDownloadNotice(.album(name: album.name, queuedCount: queuedCount))
        }
        saveIncompleteDownloads()
        processQueue()
    }

    func downloadPlaylist(_ playlist: Playlist) {
        print("📥 Downloading playlist: \(playlist.name)")
        guard let songs = playlist.entry else { return }
        var queuedCount = 0
        // Add all songs to the queue first, then process
        for song in songs {
            guard !isDownloaded(song.id) && !isDownloading(song.id) else {
                print("⏭️ Song already downloaded or downloading: \(song.title)")
                continue
            }

            guard !downloadQueue.contains(where: { $0.id == song.id }) else {
                print("⏳ Song already queued: \(song.title)")
                continue
            }

            downloadQueue.append(song)
            songMetadata[song.id] = song
            sessionTotalCount += 1
            queuedCount += 1
            print("📋 Added to queue: \(song.title)")
        }
        if queuedCount > 0 {
            saveSongMetadata()
            showDownloadNotice(.playlist(name: playlist.name, queuedCount: queuedCount))
        }
        saveIncompleteDownloads()
        processQueue()
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
        if failedDownloads.removeValue(forKey: songId) != nil {
            songMetadata.removeValue(forKey: songId)
            saveSongMetadata()
            saveIncompleteDownloads()
            return
        }

        // Cancel active download
        if let task = downloadTasks[songId] {
            task.cancel()
            print("🛑 Cancelled download for song: \(songId)")

            activeDownloads.removeValue(forKey: songId)
            downloadBytesReceived.removeValue(forKey: songId)
            downloadTotalBytes.removeValue(forKey: songId)
            downloadTasks.removeValue(forKey: songId)
            taskToSongId.removeValue(forKey: task)
            _ = Self.completionContextStore.removeContext(for: task.taskIdentifier)
            songMetadata.removeValue(forKey: songId)

            // Decrement session total since we're cancelling
            if sessionTotalCount > 0 {
                sessionTotalCount -= 1
            }

            // Process next in queue
            if !isPaused {
                saveIncompleteDownloads()
                processQueue()
            } else {
                saveIncompleteDownloads()
            }
            return
        }

        // Remove from queue
        if let index = downloadQueue.firstIndex(where: { $0.id == songId }) {
            let song = downloadQueue.remove(at: index)
            songMetadata.removeValue(forKey: songId)

            // Decrement session total since we're removing from queue
            if sessionTotalCount > 0 {
                sessionTotalCount -= 1
            }

            print("🛑 Removed from queue: \(song.title)")
            saveIncompleteDownloads()
        }
    }

    func retryDownload(_ songId: String) {
        // Get song metadata
        guard let song = songMetadata[songId] else {
            print("❌ No metadata found for retry: \(songId)")
            return
        }

        print("🔄 Retrying download: \(song.title)")
        failedDownloads.removeValue(forKey: songId)

        // Cancel existing download if active
        if let task = downloadTasks[songId] {
            task.cancel()
            activeDownloads.removeValue(forKey: songId)
            downloadBytesReceived.removeValue(forKey: songId)
            downloadTasks.removeValue(forKey: songId)
            taskToSongId.removeValue(forKey: task)
            _ = Self.completionContextStore.removeContext(for: task.taskIdentifier)
        }

        // Re-add to queue
        downloadQueue.insert(song, at: 0) // Add to front of queue
        saveIncompleteDownloads()
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

    // MARK: - Complete Data Cleanup (for logout)

    func deleteAllUserData() {
        print("🗑️ Starting complete user data cleanup for logout...")

        // 1. Cancel all active downloads
        print("🗑️ Cancelling all downloads...")
        cancelAllDownloads()

        // 2. Delete all downloaded music files
        print("🗑️ Deleting all music files...")
        do {
            let downloadsDir = downloadsDirectory
            if fileManager.fileExists(atPath: downloadsDir.path) {
                let files = try fileManager.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: nil)
                for file in files {
                    try fileManager.removeItem(at: file)
                    print("🗑️ Deleted: \(file.lastPathComponent)")
                }
            }
        } catch {
            print("❌ Error deleting music files: \(error)")
        }

        // 3. Delete all metadata JSON files
        print("🗑️ Deleting metadata files...")
        let metadataFiles = [
            metadataURL,              // downloads.json
            songMetadataURL,          // song_metadata.json
            playlistsMetadataURL,     // playlists.json
            radioPlaylistsURL,        // radio_playlists.json
            starredSongsURL,          // starred_songs.json
            pendingStarChangesURL,    // pending_star_changes.json
            pendingUnstarChangesURL,  // pending_unstar_changes.json
            incompleteDownloadsURL    // incomplete_downloads.json
        ]

        for metadataFile in metadataFiles {
            do {
                if fileManager.fileExists(atPath: metadataFile.path) {
                    try fileManager.removeItem(at: metadataFile)
                    print("🗑️ Deleted: \(metadataFile.lastPathComponent)")
                }
            } catch {
                print("❌ Error deleting \(metadataFile.lastPathComponent): \(error)")
            }
        }
        StoredAlbumArtworkCache.removeAllStoredArtwork()

        // 4. Clear all in-memory caches
        print("🗑️ Clearing in-memory caches...")
        downloadedSongs.removeAll()
        songMetadata.removeAll()
        cachedPlaylists.removeAll()
        radioPlaylists.removeAll()
        starredSongIds.removeAll()
        pendingStarChanges.removeAll()
        pendingUnstarChanges.removeAll()
        downloadQueue.removeAll()
        activeDownloads.removeAll()
        failedDownloads.removeAll()
        downloadTasks.removeAll()
        taskToSongId.removeAll()
        Self.completionContextStore.removeAll()
        downloadBytesReceived.removeAll()
        downloadTotalBytes.removeAll()
        pendingProgressUpdates.removeAll()

        // 5. Reset session counters
        sessionBytesDownloaded = 0
        sessionBytesTotal = 0
        sessionCompletedCount = 0
        sessionTotalCount = 0
        isPaused = false

        print("✅ User data cleanup complete")
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

    func cacheArtworkForDownloadedSongs() async {
        let coverArtIds = Set(
            Array(songMetadata.values.compactMap(\.coverArt)) +
            Array(downloadedSongs.values.compactMap(\.coverArt))
        )
        for coverArtId in coverArtIds {
            await StoredAlbumArtworkCache.persistIfEnabled(coverArtId: coverArtId)
        }
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
        bytes.formatted(.byteCount(style: .file))
    }
}
