//
//  NavidromeAPI.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import CryptoKit
import Combine

class DownloadProgressDelegate: NSObject, URLSessionDataDelegate {
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

class NavidromeAPI: ObservableObject {
    static let shared = NavidromeAPI()

    @Published var isAuthenticated = false

    private var baseURL: String
    private var username: String
    private var password: String

    private let clientName = "Navidream"
    private let apiVersion = "1.16.1"

    init() {
        // Load saved credentials
        self.baseURL = UserDefaults.standard.string(forKey: "navidrome_url") ?? ""
        self.username = UserDefaults.standard.string(forKey: "navidrome_username") ?? ""
        self.password = UserDefaults.standard.string(forKey: "navidrome_password") ?? ""

        self.isAuthenticated = !baseURL.isEmpty && !username.isEmpty && !password.isEmpty
    }

    func configure(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.username = username
        self.password = password

        UserDefaults.standard.set(self.baseURL, forKey: "navidrome_url")
        UserDefaults.standard.set(self.username, forKey: "navidrome_username")
        UserDefaults.standard.set(self.password, forKey: "navidrome_password")

        self.isAuthenticated = true
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: "navidrome_url")
        UserDefaults.standard.removeObject(forKey: "navidrome_username")
        UserDefaults.standard.removeObject(forKey: "navidrome_password")

        self.baseURL = ""
        self.username = ""
        self.password = ""
        self.isAuthenticated = false
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

    func getSimilarSongs(id: String, count: Int = 100) async throws -> [Song] {
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

        // Handle both nil similarSongs and nil song array
        if let similarSongs = result.subsonicResponse.similarSongs,
           let songs = similarSongs.song {
            return songs
        }
        return []
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

        // Handle both nil similarSongs and nil song array
        if let similarSongs = result.subsonicResponse.similarSongs,
           let songs = similarSongs.song {
            return songs
        }
        return []
    }

    func getCoverArtURL(id: String, size: Int = 300) -> URL? {
        return buildURL(endpoint: "getCoverArt", additionalParams: ["id": id, "size": String(size)])
    }

    func getStreamURL(id: String, format: String = "mp3", maxBitRate: Int = 128) -> URL? {
        let url = buildURL(endpoint: "stream", additionalParams: [
            "id": id,
            "format": format,
            "maxBitRate": String(maxBitRate)
        ])
        print("🔊 Stream URL built: \(url?.absoluteString ?? "nil")")
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
            return "Invalid URL"
        case .authenticationFailed:
            return "Authentication failed"
        case .apiError(let message):
            return message
        case .unknown:
            return "Unknown error"
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

struct Artist: Decodable, Identifiable {
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

struct AlbumSummary: Decodable, Identifiable {
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

struct Song: Decodable, Identifiable {
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
