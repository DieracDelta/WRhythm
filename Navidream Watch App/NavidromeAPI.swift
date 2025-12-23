//
//  NavidromeAPI.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import Foundation
import CryptoKit
import Combine

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

    func getArtists() async throws -> [Artist] {
        guard let url = buildURL(endpoint: "getArtists") else {
            print("❌ Invalid URL for getArtists")
            throw NavidromeError.invalidURL
        }

        print("🔍 Fetching artists from: \(url.absoluteString)")

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

    func getCoverArtURL(id: String, size: Int = 300) -> URL? {
        return buildURL(endpoint: "getCoverArt", additionalParams: ["id": id, "size": String(size)])
    }

    func getStreamURL(id: String) -> URL? {
        return buildURL(endpoint: "stream", additionalParams: ["id": id])
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

struct AlbumResponse: Decodable {
    let status: String
    let version: String
    let error: SubsonicError?
    let album: Album?
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
