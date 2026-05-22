//
//  ArtistDetailView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ArtistDetailView: View {
    let artistId: String
    let artistName: String

    @State private var artist: ArtistWithAlbums?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var player: AudioPlayer { AudioPlayer.shared }

    private func filteredAlbums(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        if offlineMode {
            return albums.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
        }
        return albums
    }

    var body: some View {
        content
        .navigationTitle(artistName)
        .onAppear {
            if !offlineMode {
                loadArtist()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if offlineMode {
            offlineArtistContent
        } else if isLoading {
            WRhythmLoadingState(
                systemImage: "person.2",
                title: "Loading artist",
                message: nil
            )
            .wrhythmPageBackground()
        } else if !errorMessage.isEmpty {
            WRhythmErrorState(
                title: "Artist Error",
                message: errorMessage
            ) {
                loadArtist()
            }
            .wrhythmPageBackground()
        } else if let artist {
            onlineArtistContent(artist)
        }
    }

    @ViewBuilder
    private var offlineArtistContent: some View {
        let albums = downloadedAlbumSummaries(for: artistName)
        WRhythmScreen(coverArtId: albums.first?.coverArt) {
            WRhythmHeroHeader(
                title: artistName,
                subtitle: "\(albums.count) downloaded album\(albums.count == 1 ? "" : "s")",
                detail: "Offline artist",
                systemImage: "person.fill",
                tint: .indigo,
                coverArtId: albums.first?.coverArt
            ) {
                WRhythmActionStrip {
                    Button(action: {
                        playAllDownloadedSongs(for: artistName)
                    }) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(albums.isEmpty)

                    Button(action: {
                        shuffleAllDownloadedSongs(for: artistName)
                    }) {
                        Image(systemName: "shuffle")
                    }
                    .disabled(albums.isEmpty)

                    artistRadioLink()
                }
            }

            if albums.isEmpty {
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No downloaded albums",
                    message: "Download music while online to access this artist offline"
                )
            } else {
                albumSection(albums: albums)
            }
        }
    }

    private func onlineArtistContent(_ artist: ArtistWithAlbums) -> some View {
        let albums = filteredAlbums(artist.album)
        return WRhythmScreen(coverArtId: albums.first?.coverArt) {
            WRhythmHeroHeader(
                title: artistName,
                subtitle: "\(albums.count) album\(albums.count == 1 ? "" : "s")",
                detail: "Artist",
                systemImage: "person.fill",
                tint: .indigo,
                coverArtId: albums.first?.coverArt
            ) {
                WRhythmActionStrip {
                    Button(action: {
                        playAllSongs(artist)
                    }) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(albums.isEmpty)

                    Button(action: {
                        shuffleAllSongs(artist)
                    }) {
                        Image(systemName: "shuffle")
                    }
                    .disabled(albums.isEmpty)

                    artistRadioLink()

                    if isArtistDownloaded(artist) {
                        Button(action: {
                            deleteArtist(artist)
                        }) {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    } else {
                        Button(action: {
                            downloadArtist(artist)
                        }) {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
            }

            albumSection(albums: albums)
        }
    }

    private func albumSection(albums: [AlbumSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WRhythmSectionHeader(
                title: "Albums",
                subtitle: "\(albums.count) album\(albums.count == 1 ? "" : "s")"
            )

            WRhythmCard(padding: 10) {
                VStack(spacing: 0) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                            WRhythmCollectionRow(
                                title: album.name,
                                subtitle: album.year.map(String.init),
                                coverArtId: album.coverArt,
                                fallbackSystemImage: "square.stack",
                                tint: .teal
                            ) {
                                if isAlbumDownloaded(album.id) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .wrhythmAlbumActions(albumId: album.id, albumName: album.name)
                    }
                }
            }
        }
    }

    private func artistRadioLink() -> some View {
        NavigationLink(destination: RadioOptionsView(
            sourceSong: Song(
                id: artistId,
                title: artistName,
                album: nil,
                albumId: nil,
                artist: artistName,
                artistId: artistId,
                track: nil,
                year: nil,
                genre: nil,
                coverArt: nil,
                size: nil,
                contentType: nil,
                suffix: nil,
                duration: nil,
                bitRate: nil,
                path: nil
            ),
            sourceTitle: artistName,
            sourceType: .artist
        )) {
            Image(systemName: "music.note.list")
        }
    }

    private func downloadedAlbumSummaries(for artistName: String) -> [AlbumSummary] {
        downloadManager.getDownloadedAlbums()
            .filter { $0.artist == artistName }
            .map { album in
                AlbumSummary(
                    id: album.id,
                    name: album.name,
                    artist: album.artist,
                    artistId: nil,
                    coverArt: album.coverArt,
                    songCount: 0,
                    duration: 0,
                    created: "",
                    year: nil
                )
            }
    }

    private func loadArtist() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedArtist = try await NavidromeAPI.shared.getArtist(id: artistId)
                await MainActor.run {
                    self.artist = fetchedArtist
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func isAlbumDownloaded(_ albumId: String) -> Bool {
        // Check if any song from this album is downloaded
        return downloadManager.downloadedSongs.values.contains { song in
            guard let album = song.album else { return false }
            return album == albumId
        }
    }

    private func isArtistDownloaded(_ artist: ArtistWithAlbums) -> Bool {
        // Check if at least one album has downloaded songs
        return artist.album.contains { isAlbumDownloaded($0.id) }
    }

    private func downloadArtist(_ artist: ArtistWithAlbums) {
        Task {
            await downloadManager.downloadArtist(artist)
        }
    }

    private func deleteArtist(_ artist: ArtistWithAlbums) {
        Task {
            for albumSummary in artist.album {
                do {
                    let album = try await NavidromeAPI.shared.getAlbum(id: albumSummary.id)
                    await MainActor.run {
                        downloadManager.deleteAlbum(album)
                    }
                } catch {
                    print("❌ Failed to fetch album \(albumSummary.name) for deletion: \(error)")
                }
            }
        }
    }

    private func playAllSongs(_ artist: ArtistWithAlbums) {
        Task {
            var allSongs: [Song] = []

            // Fetch all songs from all albums
            for albumSummary in artist.album {
                do {
                    let album = try await NavidromeAPI.shared.getAlbum(id: albumSummary.id)
                    allSongs.append(contentsOf: album.song)
                } catch {
                    print("❌ Failed to fetch album \(albumSummary.name): \(error)")
                }
            }

            guard !allSongs.isEmpty else {
                print("⚠️ No songs found for artist")
                return
            }

            await MainActor.run {
                player.playQueue(allSongs, startingAt: 0)
            }
        }
    }

    private func shuffleAllSongs(_ artist: ArtistWithAlbums) {
        Task {
            var allSongs: [Song] = []

            // Fetch all songs from all albums
            for albumSummary in artist.album {
                do {
                    let album = try await NavidromeAPI.shared.getAlbum(id: albumSummary.id)
                    allSongs.append(contentsOf: album.song)
                } catch {
                    print("❌ Failed to fetch album \(albumSummary.name): \(error)")
                }
            }

            guard !allSongs.isEmpty else {
                print("⚠️ No songs found for artist")
                return
            }

            await MainActor.run {
                player.playQueueShuffled(allSongs)
            }
        }
    }

    private func playAllDownloadedSongs(for artistName: String) {
        let downloadedSongs = downloadManager.downloadedSongs.values.filter { $0.artist == artistName }
        let songs = downloadedSongs.map { downloaded in
            Song(
                id: downloaded.songId,
                title: downloaded.title,
                album: downloaded.album,
                albumId: downloaded.album,
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
                path: nil
            )
        }

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs found for artist: \(artistName)")
            return
        }

        player.playQueue(songs, startingAt: 0)
    }

    private func shuffleAllDownloadedSongs(for artistName: String) {
        let downloadedSongs = downloadManager.downloadedSongs.values.filter { $0.artist == artistName }
        let songs = downloadedSongs.map { downloaded in
            Song(
                id: downloaded.songId,
                title: downloaded.title,
                album: downloaded.album,
                albumId: downloaded.album,
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
                path: nil
            )
        }

        guard !songs.isEmpty else {
            print("⚠️ No downloaded songs found for artist: \(artistName)")
            return
        }

        player.playQueueShuffled(songs)
    }

    private func startRadioFromArtist() {
        Task {
            do {
                print("🎵 Starting radio for artist: \(artistName)")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: 100)
                print("📻 getSimilarSongs2 returned \(similarSongs.count) songs for artist")

                // Fallback: Try random songs if no artist-based results
                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: 100)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found even with fallbacks")
                    } else {
                        print("✅ Radio queue ready with \(similarSongs.count) songs")
                        player.playQueueShuffled(similarSongs)
                        print("📻 Queue after playQueueShuffled: \(player.queue.count) songs")
                    }
                }
            } catch {
                print("❌ Failed to start radio for artist: \(error)")
            }
        }
    }
}
