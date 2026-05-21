//
//  NavidromeAPI.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import CryptoKit
import Combine

final class DownloadProgressDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let progressHandler: (Double, Int64, Int64) -> Void
    private var expectedBytes: Int64 = 0
    private var receivedBytes: Int64 = 0
    private var receivedData = Data()
    private var urlResponse: URLResponse?

    init(progressHandler: @escaping (Double, Int64, Int64) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        urlResponse = response
        expectedBytes = response.expectedContentLength
        print("📊 Expected bytes: \(expectedBytes)")
        Task { @MainActor in
            progressHandler(0, 0, expectedBytes)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        receivedBytes += Int64(data.count)
        let progress = expectedBytes > 0 ? Double(receivedBytes) / Double(expectedBytes) : 0
        print("📊 Progress: \(receivedBytes)/\(expectedBytes) = \(Int(progress * 100))%")
        Task { @MainActor in
            progressHandler(progress, receivedBytes, expectedBytes)
        }
    }

    func download(with request: URLRequest) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.dataTask(with: request) { data, response, error in
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

    private var baseURL: String
    private var username: String
    private var password: String

    private let clientName = "WRhythm"
    private let apiVersion = "1.16.1"

    var hasCredentials: Bool {
        !baseURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    init() {
        // Load saved credentials
        self.baseURL = UserDefaults.standard.string(forKey: "navidrome_url") ?? ""
        self.username = UserDefaults.standard.string(forKey: "navidrome_username") ?? ""
        self.password = UserDefaults.standard.string(forKey: "navidrome_password") ?? ""

        self.isAuthenticated = !baseURL.isEmpty && !username.isEmpty && !password.isEmpty

        // Load cached transcoding support status
        if UserDefaults.standard.object(forKey: "server_supports_transcoding") != nil {
            self.transcodingSupported = UserDefaults.standard.bool(forKey: "server_supports_transcoding")
        }
    }

    func configure(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.username = username
        self.password = password

        UserDefaults.standard.set(self.baseURL, forKey: "navidrome_url")
        UserDefaults.standard.set(self.username, forKey: "navidrome_username")
        UserDefaults.standard.set(self.password, forKey: "navidrome_password")

        self.isAuthenticated = true
        DeviceSyncManager.shared.credentialsDidChange()
    }

    func validateAndConfigure(baseURL: String, username: String, password: String) async throws -> Bool {
        // Save original credentials in case validation fails
        let originalBaseURL = self.baseURL
        let originalUsername = self.username
        let originalPassword = self.password
        let originalAuth = self.isAuthenticated

        // Temporarily set credentials WITHOUT saving to UserDefaults
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.username = username
        self.password = password

        do {
            // Validate with server first
            let success = try await ping()

            if success {
                // Validation succeeded - NOW save to UserDefaults
                UserDefaults.standard.set(self.baseURL, forKey: "navidrome_url")
                UserDefaults.standard.set(self.username, forKey: "navidrome_username")
                UserDefaults.standard.set(self.password, forKey: "navidrome_password")
                self.isAuthenticated = true
                DeviceSyncManager.shared.credentialsDidChange()

                // Check transcoding support after successful login
                Task { @MainActor in
                    await self.checkTranscodingSupport()
                }

                return true
            } else {
                // Validation failed - restore original credentials
                self.baseURL = originalBaseURL
                self.username = originalUsername
                self.password = originalPassword
                self.isAuthenticated = originalAuth
                return false
            }
        } catch {
            // Error occurred - restore original credentials
            self.baseURL = originalBaseURL
            self.username = originalUsername
            self.password = originalPassword
            self.isAuthenticated = originalAuth
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
        print("🔓 Cleared credentials")

        // 5. Clear API state
        self.baseURL = ""
        self.username = ""
        self.password = ""
        self.isAuthenticated = false
        DeviceSyncManager.shared.credentialsDidChange()

        // NOTE: radioDownloadCount is preserved (app-level setting)

        print("✅ Logout complete")
    }

    func exportCredentialsForSync() -> SyncedCredentials? {
        guard hasCredentials else { return nil }
        return SyncedCredentials(baseURL: baseURL, username: username, password: password)
    }

    @discardableResult
    func importCredentialsIfMissing(_ credentials: SyncedCredentials) -> Bool {
        guard !hasCredentials, !isAuthenticated else {
            print("🔐 Skipped credential import because this device already has credentials")
            return false
        }

        configure(
            baseURL: credentials.baseURL,
            username: credentials.username,
            password: credentials.password
        )
        print("🔐 Imported credentials from a trusted nearby WRhythm device")
        return true
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

    private func generateAuthParams() -> [String: String] {
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

    private func buildURL(endpoint: String, additionalParams: [String: String] = [:]) -> URL? {
        var components = URLComponents(string: "\(baseURL)/rest/\(endpoint)")
        var params = generateAuthParams()
        params.merge(additionalParams) { _, new in new }
        components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    func ping() async throws -> Bool {
        guard let url = buildURL(endpoint: "ping") else {
            print("❌ Invalid URL for ping")
            throw NavidromeError.invalidURL
        }

        print("🔍 Pinging: \(url.absoluteString)")

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

    func getArtists(progressHandler: ((Double, Int64, Int64) -> Void)? = nil) async throws -> [Artist] {
        guard let url = buildURL(endpoint: "getArtists") else {
            print("❌ Invalid URL for getArtists")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching artists from: \(url.absoluteString)")

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

    func getAlbumList(type: String = "newest", size: Int = 20, offset: Int = 0, progressHandler: ((Double, Int64, Int64) -> Void)? = nil) async throws -> [AlbumSummary] {
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
        if let artistId = song.artistId {
            let songs = try await getSimilarSongs2(artistId: artistId, count: count)
            if !songs.isEmpty {
                return songs
            }
        }

        // Legacy fallback for servers or metadata where the source song has no
        // ID3 artist ID. Prefer getSimilarSongs2 above for normal Navidrome use.
        return try await getSimilarSongs(id: song.id, count: count)
    }

    private func getSimilarSongs(id: String, count: Int = 100) async throws -> [Song] {
        guard let url = buildURL(endpoint: "getSimilarSongs", additionalParams: [
            "id": id,
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
            print("🔊 Stream URL built (format: \(format), maxBitRate: \(maxBitRate.map(String.init) ?? "original")): \(url?.absoluteString ?? "nil")")
        } else {
            print("🔊 Stream URL built (maxBitRate: \(maxBitRate.map(String.init) ?? "original")): \(url?.absoluteString ?? "nil")")
        }
        return url
    }

    func getPlaylists() async throws -> [PlaylistSummary] {
        guard let url = buildURL(endpoint: "getPlaylists") else {
            print("❌ Invalid URL for getPlaylists")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching playlists from: \(url.absoluteString)")

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

        print("🔍 Fetching starred content from: \(url.absoluteString)")

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
    let similarSongs: SimilarSongs?
    let similarSongs2: SimilarSongs?

    var songs: [Song] {
        similarSongs2?.song ?? similarSongs?.song ?? []
    }
}

struct SimilarSongs: Decodable {
    let song: [Song]?
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
