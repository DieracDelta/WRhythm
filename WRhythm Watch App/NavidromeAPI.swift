//
//  NavidromeAPI.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import CryptoKit
import Combine

typealias DownloadProgressHandler = @MainActor @Sendable (Double, Int64, Int64) -> Void

actor DownloadProgressState {
    private var expectedBytes: Int64 = 0
    private var receivedBytes: Int64 = 0

    func reset(expectedBytes: Int64) -> (progress: Double, receivedBytes: Int64, expectedBytes: Int64) {
        self.expectedBytes = expectedBytes
        self.receivedBytes = 0
        return (0, 0, expectedBytes)
    }

    func append(byteCount: Int) -> (progress: Double, receivedBytes: Int64, expectedBytes: Int64) {
        receivedBytes += Int64(byteCount)
        let progress = expectedBytes > 0 ? Double(receivedBytes) / Double(expectedBytes) : 0
        return (progress, receivedBytes, expectedBytes)
    }
}

private struct DownloadResponseCompletion: @unchecked Sendable {
    let handler: (URLSession.ResponseDisposition) -> Void

    func callAsFunction(_ disposition: URLSession.ResponseDisposition) {
        handler(disposition)
    }
}

final class DownloadProgressDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let progressHandler: DownloadProgressHandler
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "WRhythm.DownloadProgressDelegate"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let state = DownloadProgressState()

    init(progressHandler: @escaping DownloadProgressHandler) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let expectedBytes = response.expectedContentLength
        let completion = DownloadResponseCompletion(handler: completionHandler)
        print("📊 Expected bytes: \(expectedBytes)")
        Task { [state, progressHandler, completion] in
            let update = await state.reset(expectedBytes: expectedBytes)
            await progressHandler(update.progress, update.receivedBytes, update.expectedBytes)
            await MainActor.run {
                completion(.allow)
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let byteCount = data.count
        Task { [state, progressHandler] in
            let update = await state.append(byteCount: byteCount)
            print("📊 Progress: \(update.receivedBytes)/\(update.expectedBytes) = \(Int(update.progress * 100))%")
            await progressHandler(update.progress, update.receivedBytes, update.expectedBytes)
        }
    }

    func download(with request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
            let task = session.dataTask(with: request) { data, response, error in
                defer { session.finishTasksAndInvalidate() }
                print("📊 Download completed - data: \(data?.count ?? 0) bytes, response: \(response != nil), error: \(error?.localizedDescription ?? "none")")

                if let error = error {
                    print("❌ Download error: \(error)")
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    print("✅ Download successful: \(data.count) bytes")
                    continuation.resume(returning: (data, response))
                } else {
                    print("❌ Download completed but missing data or response")
                    continuation.resume(throwing: NavidromeError.unknown)
                }
            }
            print("📊 Starting download task...")
            task.resume()
        }
    }
}

@MainActor
final class NavidromeAPI: ObservableObject {
    static let shared = NavidromeAPI()

    @Published var isAuthenticated = false
    @Published var transcodingSupported: Bool? = nil  // nil = not yet checked
    @Published var isCheckingTranscoding: Bool = false
    @Published var sonicSimilaritySupported: Bool? = nil
    @Published var audioMuseAlchemySupported: Bool? = nil

    private var baseURL: String
    private var username: String
    private var password: String
    private var credentialIssuedAt: Date
    private var credentialClearedAt: Date
    private var credentialSyncAuthorizedAt: Date

    private let clientName = "WRhythm"
    private let apiVersion = "1.16.1"
    private static let credentialIssuedAtKey = "navidrome_credentials_issued_at"
    private static let credentialClearedAtKey = "navidrome_credentials_cleared_at"
    private static let credentialSyncAuthorizedAtKey = "navidrome_credential_sync_authorized_at"

    var hasCredentials: Bool {
        !baseURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    init() {
        // Load saved credentials
        self.baseURL = UserDefaults.standard.string(forKey: "navidrome_url") ?? ""
        self.username = UserDefaults.standard.string(forKey: "navidrome_username") ?? ""
        self.password = UserDefaults.standard.string(forKey: "navidrome_password") ?? ""

        let hasSavedCredentials = !baseURL.isEmpty && !username.isEmpty && !password.isEmpty
        self.isAuthenticated = hasSavedCredentials
        self.credentialClearedAt = UserDefaults.standard.object(forKey: Self.credentialClearedAtKey) as? Date ?? .distantPast
        self.credentialSyncAuthorizedAt = UserDefaults.standard.object(forKey: Self.credentialSyncAuthorizedAtKey) as? Date ?? .distantPast
        if let issuedAt = UserDefaults.standard.object(forKey: Self.credentialIssuedAtKey) as? Date {
            self.credentialIssuedAt = issuedAt
        } else {
            self.credentialIssuedAt = hasSavedCredentials ? Date() : .distantPast
            if hasSavedCredentials {
                UserDefaults.standard.set(self.credentialIssuedAt, forKey: Self.credentialIssuedAtKey)
            }
        }

        // Load cached transcoding support status
        if UserDefaults.standard.object(forKey: "server_supports_transcoding") != nil {
            self.transcodingSupported = UserDefaults.standard.bool(forKey: "server_supports_transcoding")
        }
        if UserDefaults.standard.object(forKey: "server_supports_sonic_similarity") != nil {
            self.sonicSimilaritySupported = UserDefaults.standard.bool(forKey: "server_supports_sonic_similarity")
        }
        if UserDefaults.standard.object(forKey: "server_supports_audiomuse_alchemy") != nil {
            self.audioMuseAlchemySupported = UserDefaults.standard.bool(forKey: "server_supports_audiomuse_alchemy")
        }
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func applyCredentials(_ credentials: SyncedCredentials, notifySync: Bool = true) {
        self.baseURL = normalizedBaseURL(credentials.baseURL)
        self.username = credentials.username
        self.password = credentials.password

        UserDefaults.standard.set(self.baseURL, forKey: "navidrome_url")
        UserDefaults.standard.set(self.username, forKey: "navidrome_username")
        UserDefaults.standard.set(self.password, forKey: "navidrome_password")

        let issuedAt = credentials.issuedAt
        self.credentialIssuedAt = issuedAt
        UserDefaults.standard.set(issuedAt, forKey: Self.credentialIssuedAtKey)

        self.isAuthenticated = true
        sonicSimilaritySupported = nil
        audioMuseAlchemySupported = nil
        UserDefaults.standard.removeObject(forKey: "server_supports_sonic_similarity")
        UserDefaults.standard.removeObject(forKey: "server_supports_audiomuse_alchemy")
        if notifySync {
            DeviceSyncManager.shared.credentialsDidChange()
        }
    }

    func configure(baseURL: String, username: String, password: String) {
        applyCredentials(SyncedCredentials(
            baseURL: baseURL,
            username: username,
            password: password,
            issuedAt: Date()
        ))
    }

    func validateAndConfigure(baseURL: String, username: String, password: String) async throws -> Bool {
        let candidate = SyncedCredentials(
            baseURL: normalizedBaseURL(baseURL),
            username: username,
            password: password,
            issuedAt: Date()
        )

        do {
            // Validate with server first, without publishing candidate credentials
            // through shared state while the network request is suspended.
            let success = try await ping(using: candidate)

            if success {
                // Validation succeeded - NOW save to UserDefaults
                applyCredentials(candidate)

                // Check transcoding support after successful login
                Task { @MainActor in
                    await self.checkTranscodingSupport()
                }

                return true
            } else {
                return false
            }
        } catch {
            throw error
        }
    }

    @MainActor
    func logout() {
        print("🔓 Starting logout process...")

        // 1. Stop any active audio playback
        AudioPlayer.shared.stop()
        print("🔓 Stopped audio playback")

        // 2. Delete all user data (downloads, metadata, etc.)
        DownloadManager.shared.deleteAllUserData()
        print("🔓 Deleted all user data")

        // 3. Reset offline mode to false (user must log in to use app)
        UserDefaults.standard.set(false, forKey: "offlineMode")
        print("🔓 Reset offline mode to false")

        // 4. Clear credentials from UserDefaults
        UserDefaults.standard.removeObject(forKey: "navidrome_url")
        UserDefaults.standard.removeObject(forKey: "navidrome_username")
        UserDefaults.standard.removeObject(forKey: "navidrome_password")
        UserDefaults.standard.removeObject(forKey: Self.credentialIssuedAtKey)
        UserDefaults.standard.removeObject(forKey: Self.credentialSyncAuthorizedAtKey)
        let clearedAt = Date()
        UserDefaults.standard.set(clearedAt, forKey: Self.credentialClearedAtKey)
        print("🔓 Cleared credentials")

        // 5. Clear API state
        self.baseURL = ""
        self.username = ""
        self.password = ""
        self.credentialIssuedAt = .distantPast
        self.credentialClearedAt = clearedAt
        self.credentialSyncAuthorizedAt = .distantPast
        self.isAuthenticated = false
        DeviceSyncManager.shared.disableCredentialSyncAfterLocalLogout()
        DeviceSyncManager.shared.credentialsDidChange()

        // NOTE: radioDownloadCount is preserved (app-level setting)

        print("✅ Logout complete")
    }

    func exportCredentialsForSync() -> SyncedCredentials? {
        guard hasCredentials else { return nil }
        return SyncedCredentials(baseURL: baseURL, username: username, password: password, issuedAt: credentialIssuedAt)
    }

    @discardableResult
    func importCredentialsIfMissing(_ credentials: SyncedCredentials) -> Bool {
        guard !hasCredentials, !isAuthenticated else {
            print("🔐 Skipped credential import because this device already has credentials")
            return false
        }

        guard CredentialSyncPolicy.shouldImport(
            incomingIssuedAt: credentials.issuedAt,
            localClearedAt: credentialClearedAt,
            credentialSyncAuthorizedAt: credentialSyncAuthorizedAt
        ) else {
            print("🔐 Skipped stale credential import from before local logout")
            return false
        }

        applyCredentials(SyncedCredentials(
            baseURL: credentials.baseURL,
            username: credentials.username,
            password: credentials.password,
            issuedAt: credentials.issuedAt
        ))
        print("🔐 Imported credentials from a trusted nearby WRhythm device")
        return true
    }

    func authorizeCredentialImportFromTrustedSync() {
        guard !hasCredentials, !isAuthenticated else { return }
        let authorizedAt = Date()
        credentialSyncAuthorizedAt = authorizedAt
        UserDefaults.standard.set(authorizedAt, forKey: Self.credentialSyncAuthorizedAtKey)
        print("🔐 Authorized credential import from trusted sync")
    }

    // MARK: - Transcoding Support Check

    /// Checks if the server supports transcoding by probing with a test request
    /// This is necessary because the Subsonic API doesn't provide a direct capability check
    @discardableResult
    func checkTranscodingSupport() async -> Bool {
        print("🔍 Checking server transcoding support...")

        isCheckingTranscoding = true

        defer {
            isCheckingTranscoding = false
        }

        do {
            // Get a random song to test with
            let songs = try await getRandomSongs(size: 1)
            guard let testSong = songs.first else {
                print("⚠️ No songs available to test transcoding")
                // Assume supported if we can't test (better UX)
                await updateTranscodingSupport(true)
                return true
            }

            print("🔍 Testing transcoding with song: \(testSong.title)")

            // Build a stream URL with format=mp3 to request transcoding
            guard let testURL = getStreamURL(id: testSong.id, format: "mp3", maxBitRate: 64) else {
                print("❌ Failed to build test stream URL")
                await updateTranscodingSupport(false)
                return false
            }

            // Make a HEAD request to check response without downloading the whole file
            var request = URLRequest(url: testURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type for transcoding check")
                await updateTranscodingSupport(false)
                return false
            }

            print("📡 Transcoding check response: HTTP \(httpResponse.statusCode)")

            // Check if server returned success
            if httpResponse.statusCode == 200 {
                // Check Content-Type header
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                print("📡 Content-Type: \(contentType)")

                // If it's audio/mpeg, transcoding is working
                let supported = contentType.lowercased().contains("audio/mpeg") ||
                               contentType.lowercased().contains("audio/mp3")

                if supported {
                    print("✅ Server supports transcoding (Content-Type: \(contentType))")
                } else {
                    // Server might still support it, just returning different content type
                    // Be optimistic if we got HTTP 200
                    print("⚠️ Got HTTP 200 but Content-Type is \(contentType). Assuming transcoding supported.")
                }
                await updateTranscodingSupport(true)
                return true
            } else if httpResponse.statusCode == 501 || httpResponse.statusCode == 500 {
                // Server explicitly doesn't support transcoding
                print("❌ Server does not support transcoding (HTTP \(httpResponse.statusCode))")
                await updateTranscodingSupport(false)
                return false
            } else {
                // Other error - assume supported (better UX, will fail gracefully on download)
                print("⚠️ Unexpected response \(httpResponse.statusCode), assuming transcoding supported")
                await updateTranscodingSupport(true)
                return true
            }
        } catch {
            print("❌ Error checking transcoding support: \(error)")
            // On error, assume supported (optimistic approach)
            await updateTranscodingSupport(true)
            return true
        }
    }

    private func updateTranscodingSupport(_ supported: Bool) async {
        transcodingSupported = supported
        UserDefaults.standard.set(supported, forKey: "server_supports_transcoding")
        print("💾 Cached transcoding support: \(supported)")
    }

    private func generateAuthParams(username: String? = nil, password: String? = nil) -> [String: String] {
        let username = username ?? self.username
        let password = password ?? self.password
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return [
            "u": username,
            "t": token,
            "s": salt,
            "c": clientName,
            "v": apiVersion,
            "f": "json"
        ]
    }

    private func buildURL(endpoint: String, additionalParams: [String: String] = [:], credentials: SyncedCredentials? = nil) -> URL? {
        let requestBaseURL = credentials?.baseURL ?? baseURL
        let requestUsername = credentials?.username ?? username
        let requestPassword = credentials?.password ?? password
        var components = URLComponents(string: "\(requestBaseURL)/rest/\(endpoint)")
        var params = generateAuthParams(username: requestUsername, password: requestPassword)
        params.merge(additionalParams) { _, new in new }
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    private func buildAudioMuseAPIURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(string: "\(baseURL)\(path)")
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }

    func ping() async throws -> Bool {
        try await ping(using: nil)
    }

    private func ping(using credentials: SyncedCredentials?) async throws -> Bool {
        guard let url = buildURL(endpoint: "ping", credentials: credentials) else {
            print("❌ Invalid URL for ping")
            throw NavidromeError.invalidURL
        }

        print("🔍 Pinging: \(WRhythmLogRedactor.redacted(url))")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("❌ Ping failed - HTTP error")
            throw NavidromeError.authenticationFailed
        }

        print("📡 Ping response status: \(httpResponse.statusCode)")

        let result = try JSONDecoder().decode(SubsonicResponse<EmptyResponse>.self, from: data)

        if result.subsonicResponse.status == "ok" {
            print("✅ Ping successful")
            return true
        } else if let error = result.subsonicResponse.error {
            print("❌ Ping error: \(error.message)")
            throw NavidromeError.apiError(error.message)
        }

        return false
    }

    func getArtists(progressHandler: DownloadProgressHandler? = nil) async throws -> [Artist] {
        guard let url = buildURL(endpoint: "getArtists") else {
            print("❌ Invalid URL for getArtists")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching artists from: \(WRhythmLogRedactor.redacted(url))")

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Use custom delegate for progress tracking if handler provided
        let (data, response): (Data, URLResponse)
        if let progressHandler = progressHandler {
            print("📊 Using progress tracking delegate")
            let delegate = DownloadProgressDelegate(progressHandler: progressHandler)
            (data, response) = try await delegate.download(with: request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw NavidromeError.unknown
        }

        print("📡 Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            print("❌ HTTP error: \(httpResponse.statusCode)")
            throw NavidromeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<ArtistsResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                print("❌ API error: \(error.message)")
                throw NavidromeError.apiError(error.message)
            }
            print("❌ Unknown API error")
            throw NavidromeError.unknown
        }

        let artists = result.subsonicResponse.artists?.index.flatMap { $0.artist } ?? []
        print("✅ Loaded \(artists.count) artists")
        return artists
    }

    func getArtist(id: String) async throws -> ArtistWithAlbums {
        guard let url = buildURL(endpoint: "getArtist", additionalParams: ["id": id]) else {
            throw NavidromeError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(SubsonicResponse<ArtistResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok",
              let artist = result.subsonicResponse.artist else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        return artist
    }

    func getAlbumList(type: String = "newest", size: Int = 20, offset: Int = 0, progressHandler: DownloadProgressHandler? = nil) async throws -> [AlbumSummary] {
        guard let url = buildURL(endpoint: "getAlbumList2", additionalParams: [
            "type": type,
            "size": String(size),
            "offset": String(offset)
        ]) else {
            print("❌ Invalid URL for getAlbumList2")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching albums: type=\(type), size=\(size), offset=\(offset)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Use custom delegate for progress tracking if handler provided
        let (data, response): (Data, URLResponse)
        if let progressHandler = progressHandler {
            print("📊 Using progress tracking delegate for albums")
            let delegate = DownloadProgressDelegate(progressHandler: progressHandler)
            (data, response) = try await delegate.download(with: request)
        } else {
            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw NavidromeError.unknown
        }

        print("📡 Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            print("❌ HTTP error: \(httpResponse.statusCode)")
            throw NavidromeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<AlbumListResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                print("❌ API error: \(error.message)")
                throw NavidromeError.apiError(error.message)
            }
            print("❌ Unknown API error")
            throw NavidromeError.unknown
        }

        let albums = result.subsonicResponse.albumList2?.album ?? []
        print("✅ Loaded \(albums.count) albums")
        return albums
    }

    func getAlbum(id: String) async throws -> Album {
        guard let url = buildURL(endpoint: "getAlbum", additionalParams: ["id": id]) else {
            throw NavidromeError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(SubsonicResponse<AlbumResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok",
              let album = result.subsonicResponse.album else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        return album
    }

    func getRandomSongs(size: Int = 50) async throws -> [Song] {
        guard let url = buildURL(endpoint: "getRandomSongs", additionalParams: ["size": String(size)]) else {
            throw NavidromeError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(SubsonicResponse<RandomSongsResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        return result.subsonicResponse.randomSongs?.song ?? []
    }

    func getSimilarSongsForSong(_ song: Song, count: Int = 100) async throws -> [Song] {
        guard let artistId = song.artistId else { return [] }
        return try await getSimilarSongs2(artistId: artistId, count: count)
    }

    func getSimilarSongs2(artistId: String, count: Int = 100) async throws -> [Song] {
        guard let url = buildURL(endpoint: "getSimilarSongs2", additionalParams: [
            "id": artistId,
            "count": String(count)
        ]) else {
            throw NavidromeError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(SubsonicResponse<SimilarSongsResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        return result.subsonicResponse.songs
    }

    func checkSonicSimilaritySupport() async -> Bool {
        do {
            let extensions = try await getOpenSubsonicExtensions()
            let supported = OpenSubsonicExtensionPolicy.supportsSonicSimilarity(extensions)
            sonicSimilaritySupported = supported
            UserDefaults.standard.set(supported, forKey: "server_supports_sonic_similarity")
            return supported
        } catch {
            print("⚠️ Sonic similarity support check failed: \(error.localizedDescription)")
            sonicSimilaritySupported = false
            UserDefaults.standard.set(false, forKey: "server_supports_sonic_similarity")
            return false
        }
    }

    func getOpenSubsonicExtensions() async throws -> [OpenSubsonicExtension] {
        guard let url = buildURL(endpoint: "getOpenSubsonicExtensions") else {
            throw NavidromeError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NavidromeError.apiError("Unable to check OpenSubsonic extensions")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<OpenSubsonicExtensionsResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        return result.subsonicResponse.openSubsonicExtensions ?? []
    }

    func getSonicSimilarTracks(songId: String, count: Int = 100) async throws -> [Song] {
        guard let url = buildURL(endpoint: "getSonicSimilarTracks", additionalParams: [
            "id": songId,
            "count": String(count)
        ]) else {
            throw NavidromeError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NavidromeError.apiError("Unable to fetch sonic similar tracks")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<SonicMatchesResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        return result.subsonicResponse.songs
    }

    func findSonicPath(startSongId: String, endSongId: String, count: Int = 100) async throws -> [Song] {
        guard let url = buildURL(endpoint: "findSonicPath", additionalParams: [
            "startSongId": startSongId,
            "endSongId": endSongId,
            "count": String(count)
        ]) else {
            throw NavidromeError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NavidromeError.apiError("Unable to find sonic path")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<SonicMatchesResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        return result.subsonicResponse.songs
    }

    func checkAudioMuseAlchemySupport() async -> Bool {
        guard UserDefaults.standard.bool(forKey: "experimentalAudioMuseFeaturesEnabled") else {
            audioMuseAlchemySupported = false
            UserDefaults.standard.set(false, forKey: "server_supports_audiomuse_alchemy")
            return false
        }

        guard let url = buildAudioMuseAPIURL(
            path: "/api/alchemy/search_artists",
            queryItems: [URLQueryItem(name: "query", value: "a")]
        ) else {
            audioMuseAlchemySupported = false
            UserDefaults.standard.set(false, forKey: "server_supports_audiomuse_alchemy")
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                audioMuseAlchemySupported = false
                UserDefaults.standard.set(false, forKey: "server_supports_audiomuse_alchemy")
                return false
            }

            let supported = AudioMuseAlchemySupportPolicy.endpointExists(statusCode: httpResponse.statusCode)
            audioMuseAlchemySupported = supported
            UserDefaults.standard.set(supported, forKey: "server_supports_audiomuse_alchemy")
            return supported
        } catch {
            print("⚠️ AudioMuse Alchemy support check failed: \(error.localizedDescription)")
            audioMuseAlchemySupported = false
            UserDefaults.standard.set(false, forKey: "server_supports_audiomuse_alchemy")
            return false
        }
    }

    func getAudioMuseAlchemySongs(seedSong: Song, count: Int = 100) async throws -> [Song] {
        let jwt = try await loginToAudioMuseAPI()
        guard let url = buildAudioMuseAPIURL(path: "/api/alchemy") else {
            throw NavidromeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AudioMuseAlchemyRequest(
            items: [AudioMuseAlchemyRequest.Item(id: seedSong.id, op: "ADD", type: "song")],
            n: max(count, 1),
            temperature: 1.0,
            subtractDistance: 0.3
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NavidromeError.unknown
        }

        let decoded = try JSONDecoder().decode(AudioMuseAlchemyResponse.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode), decoded.error == nil else {
            throw NavidromeError.apiError(decoded.error ?? "AudioMuse Alchemy failed with HTTP \(httpResponse.statusCode)")
        }

        return decoded.songs
    }

    private func loginToAudioMuseAPI() async throws -> String {
        guard let url = buildAudioMuseAPIURL(path: "/api/v1/user/login") else {
            throw NavidromeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AudioMuseLoginRequest(
            username: username,
            password: password
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NavidromeError.unknown
        }

        if (200..<300).contains(httpResponse.statusCode) {
            let decoded = try JSONDecoder().decode(AudioMuseLoginResponse.self, from: data)
            return decoded.token
        }

        if let decoded = try? JSONDecoder().decode(AudioMuseAPIErrorResponse.self, from: data),
           let error = decoded.error {
            throw NavidromeError.apiError(error)
        }

        throw NavidromeError.apiError("AudioMuse login failed with HTTP \(httpResponse.statusCode)")
    }

    func getCoverArtURL(id: String, size: Int = 300) -> URL? {
        return buildURL(endpoint: "getCoverArt", additionalParams: ["id": id, "size": String(size)])
    }

    func getStreamURL(id: String, format: String? = nil, maxBitRate: Int? = nil, timeOffset: Int = 0) -> URL? {
        // Build stream URL - use .view suffix like Submariner for compatibility
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let token = Insecure.MD5.hash(data: Data((password + salt).utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var components = URLComponents(string: "\(baseURL)/rest/stream.view")

        var queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "id", value: id)
        ]

        if let maxBitRate {
            queryItems.append(URLQueryItem(name: "maxBitRate", value: String(maxBitRate)))
        }

        // Only add format if explicitly requested (for transcoding)
        if let format = format {
            queryItems.append(URLQueryItem(name: "format", value: format))
        }

        if timeOffset > 0 {
             queryItems.append(URLQueryItem(name: "timeOffset", value: String(timeOffset)))
        }

        components?.queryItems = queryItems

        let url = components?.url
        if let format = format {
            print("🔊 Stream URL built (format: \(format), maxBitRate: \(maxBitRate.map(String.init) ?? "original")): \(url.map(WRhythmLogRedactor.redacted) ?? "nil")")
        } else {
            print("🔊 Stream URL built (maxBitRate: \(maxBitRate.map(String.init) ?? "original")): \(url.map(WRhythmLogRedactor.redacted) ?? "nil")")
        }
        return url
    }

    func getPlaylists() async throws -> [PlaylistSummary] {
        guard let url = buildURL(endpoint: "getPlaylists") else {
            print("❌ Invalid URL for getPlaylists")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching playlists from: \(WRhythmLogRedactor.redacted(url))")

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw NavidromeError.unknown
        }

        print("📡 Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            print("❌ HTTP error: \(httpResponse.statusCode)")
            throw NavidromeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<PlaylistsResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                print("❌ API error: \(error.message)")
                throw NavidromeError.apiError(error.message)
            }
            print("❌ Unknown API error")
            throw NavidromeError.unknown
        }

        let playlists = result.subsonicResponse.playlists?.playlist ?? []
        print("✅ Loaded \(playlists.count) playlists")
        return playlists
    }

    func getPlaylist(id: String) async throws -> Playlist {
        guard let url = buildURL(endpoint: "getPlaylist", additionalParams: ["id": id]) else {
            print("❌ Invalid URL for getPlaylist")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching playlist: \(id)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw NavidromeError.unknown
        }

        if httpResponse.statusCode != 200 {
            print("❌ HTTP error: \(httpResponse.statusCode)")
            throw NavidromeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<PlaylistResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok",
              let playlist = result.subsonicResponse.playlist else {
            if let error = result.subsonicResponse.error {
                print("❌ API error: \(error.message)")
                throw NavidromeError.apiError(error.message)
            }
            print("❌ Unknown API error")
            throw NavidromeError.unknown
        }

        print("✅ Loaded playlist with \(playlist.entry?.count ?? 0) songs")
        return playlist
    }

    func getStarred() async throws -> StarredContent {
        guard let url = buildURL(endpoint: "getStarred2") else {
            print("❌ Invalid URL for getStarred2")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching starred content from: \(WRhythmLogRedactor.redacted(url))")

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw NavidromeError.unknown
        }

        print("📡 Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            print("❌ HTTP error: \(httpResponse.statusCode)")
            throw NavidromeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<StarredResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                print("❌ API error: \(error.message)")
                throw NavidromeError.apiError(error.message)
            }
            print("❌ Unknown API error")
            throw NavidromeError.unknown
        }

        let starred = result.subsonicResponse.starred2 ?? StarredContent(artist: [], album: [], song: [])
        print("✅ Loaded starred: \(starred.song?.count ?? 0) songs, \(starred.album?.count ?? 0) albums, \(starred.artist?.count ?? 0) artists")
        return starred
    }

    func star(songId: String) async throws {
        guard let url = buildURL(endpoint: "star", additionalParams: ["id": songId]) else {
            throw NavidromeError.invalidURL
        }

        print("⭐ Starring song: \(songId)")

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(SubsonicResponse<BaseResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        print("✅ Song starred successfully")
    }

    func unstar(songId: String) async throws {
        guard let url = buildURL(endpoint: "unstar", additionalParams: ["id": songId]) else {
            throw NavidromeError.invalidURL
        }

        print("⭐ Unstarring song: \(songId)")

        let (data, _) = try await URLSession.shared.data(from: url)
        let result = try JSONDecoder().decode(SubsonicResponse<BaseResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        print("✅ Song unstarred successfully")
    }

    func scrobble(songId: String, submission: Bool) async throws {
        guard let url = buildURL(endpoint: "scrobble.view", additionalParams: [
            "id": songId,
            "submission": submission ? "true" : "false"
        ]) else {
            throw NavidromeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NavidromeError.unknown
        }

        guard httpResponse.statusCode == 200 else {
            throw NavidromeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<BaseResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        print("✅ Scrobble \(submission ? "submission" : "now-playing") sent for song: \(songId)")
    }

    func search(query: String) async throws -> SearchResult {
        guard let url = buildURL(endpoint: "search3", additionalParams: ["query": query]) else {
            throw NavidromeError.invalidURL
        }

        print("🔍 Searching for: \(query)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NavidromeError.unknown
        }

        if httpResponse.statusCode != 200 {
            throw NavidromeError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(SubsonicResponse<SearchResponse>.self, from: data)

        guard result.subsonicResponse.status == "ok" else {
            if let error = result.subsonicResponse.error {
                throw NavidromeError.apiError(error.message)
            }
            throw NavidromeError.unknown
        }

        let searchResult = result.subsonicResponse.searchResult3 ?? SearchResult(artist: [], album: [], song: [])
        print("✅ Search returned: \(searchResult.song?.count ?? 0) songs")
        return searchResult
    }
}

enum NavidromeError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case apiError(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL. Please check the URL and try again."
        case .authenticationFailed:
            return "Authentication failed. Check your username and password, or verify the server is running."
        case .apiError(let message):
            return message
        case .unknown:
            return "Unknown error occurred. Please try again."
        }
    }
}

struct SubsonicResponse<T: Decodable>: Decodable {
    let subsonicResponse: T

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct BaseResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
}

struct SubsonicError: Decodable {
    let code: Int
    let message: String
}

struct EmptyResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
}

struct ArtistsResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let artists: Artists?
}

struct Artists: Decodable {
    let index: [ArtistIndex]
}

struct ArtistIndex: Decodable {
    let name: String
    let artist: [Artist]
}

struct Artist: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let albumCount: Int?
    let coverArt: String?
}

struct ArtistResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let artist: ArtistWithAlbums?
}

struct ArtistWithAlbums: Decodable {
    let id: String
    let name: String
    let albumCount: Int
    let coverArt: String?
    let album: [AlbumSummary]
}

struct AlbumSummary: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int
    let duration: Int
    let created: String
    let year: Int?
}

struct AlbumListResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let albumList2: AlbumList2?
}

struct AlbumList2: Decodable {
    let album: [AlbumSummary]
}

struct AlbumResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let album: Album?
}

struct RandomSongsResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let randomSongs: RandomSongs?
}

struct RandomSongs: Decodable {
    let song: [Song]
}

struct SimilarSongsResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let similarSongs2: SimilarSongs?

    var songs: [Song] {
        similarSongs2?.song ?? []
    }
}

struct SimilarSongs: Decodable {
    let song: [Song]?
}

struct OpenSubsonicExtensionsResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let openSubsonicExtensions: [OpenSubsonicExtension]?
}

struct OpenSubsonicExtension: Decodable, Sendable {
    let name: String
    let versions: [Int]?
}

enum OpenSubsonicExtensionPolicy {
    static func supportsSonicSimilarity(_ extensions: [OpenSubsonicExtension]) -> Bool {
        extensions.contains { extensionInfo in
            extensionInfo.name == "sonicSimilarity"
        }
    }
}

struct SonicMatchesResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let sonicMatch: [SonicMatch]?

    var songs: [Song] {
        sonicMatch?.map(\.entry) ?? []
    }
}

struct SonicMatch: Decodable {
    let entry: Song
    let similarity: Double?
}

enum AudioMuseAlchemySupportPolicy {
    static func endpointExists(statusCode: Int) -> Bool {
        statusCode == 200 || statusCode == 401
    }
}

struct AudioMuseLoginRequest: Encodable {
    let username: String
    let password: String
}

struct AudioMuseLoginResponse: Decodable {
    let token: String
}

struct AudioMuseAPIErrorResponse: Decodable {
    let error: String?
}

struct AudioMuseAlchemyRequest: Encodable {
    struct Item: Encodable {
        let id: String
        let op: String
        let type: String
    }

    let items: [Item]
    let n: Int
    let temperature: Double
    let subtractDistance: Double

    enum CodingKeys: String, CodingKey {
        case items
        case n
        case temperature
        case subtractDistance = "subtract_distance"
    }
}

struct AudioMuseAlchemyResponse: Decodable {
    let results: [AudioMuseAlchemyResult]?
    let error: String?

    var songs: [Song] {
        (results ?? []).compactMap(\.song)
    }
}

struct AudioMuseAlchemyResult: Decodable {
    let itemID: String?
    let id: String?
    let songID: String?
    let title: String?
    let name: String?
    let author: String?
    let artist: String?
    let album: String?
    let albumID: String?
    let coverArt: String?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case id
        case songID = "songId"
        case title
        case name
        case author
        case artist
        case album
        case albumID = "albumId"
        case coverArt
    }

    var song: Song? {
        guard let resolvedID = itemID ?? id ?? songID,
              let resolvedTitle = title ?? name else {
            return nil
        }

        return Song(
            id: resolvedID,
            title: resolvedTitle,
            album: album,
            albumId: albumID,
            artist: artist ?? author,
            artistId: nil,
            track: nil,
            year: nil,
            genre: nil,
            coverArt: coverArt ?? resolvedID,
            size: nil,
            contentType: nil,
            suffix: nil,
            duration: nil,
            bitRate: nil,
            path: nil
        )
    }
}

struct Album: Decodable, Identifiable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int
    let duration: Int
    let created: String
    let year: Int?
    let genre: String?
    let song: [Song]
}

struct Song: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let album: String?
    let albumId: String?
    let artist: String?
    let artistId: String?
    let track: Int?
    let year: Int?
    let genre: String?
    let coverArt: String?
    let size: Int?
    let contentType: String?
    let suffix: String?
    let duration: Int?
    let bitRate: Int?
    let path: String?
}

struct PlaylistsResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let playlists: Playlists?
}

struct Playlists: Decodable {
    let playlist: [PlaylistSummary]
}

struct PlaylistSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let songCount: Int
    let duration: Int
    let created: String
    let changed: String
    let coverArt: String?
    let owner: String?
    let `public`: Bool?
}

struct PlaylistResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let playlist: Playlist?
}

struct Playlist: Decodable, Identifiable {
    let id: String
    let name: String
    let songCount: Int
    let duration: Int
    let created: String
    let changed: String
    let coverArt: String?
    let owner: String?
    let `public`: Bool?
    let entry: [Song]?
}

struct StarredResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let starred2: StarredContent?
}

struct StarredContent: Decodable {
    let artist: [Artist]?
    let album: [AlbumSummary]?
    let song: [Song]?
}

struct SearchResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let searchResult3: SearchResult?
}

struct SearchResult: Decodable {
    let artist: [Artist]?
    let album: [AlbumSummary]?
    let song: [Song]?
}
