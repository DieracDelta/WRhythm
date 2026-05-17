//
//  AlbumDetailView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct SongRowView: View {
    let song: Song
    let onTap: () -> Void
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    var body: some View {
        Button(action: onTap) {
            HStack {
                if let track = song.track {
                    Text("\(track)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .leading)
                }

                VStack(alignment: .leading) {
                    Text(song.title)
                        .font(.caption)
                        .lineLimit(1)
                    if let duration = song.duration {
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if downloadManager.isDownloading(song.id) {
                    VStack(spacing: 2) {
                        ProgressView()
                            .scaleEffect(0.7)
                        let progress = downloadManager.downloadProgress(song.id)
                        if progress > 0 {
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if downloadManager.isDownloaded(song.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                if player.currentSong?.id == song.id && player.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }

                NavigationLink(destination: RadioOptionsView(
                    sourceSong: song,
                    sourceTitle: song.title,
                    sourceType: .song
                )) {
                    Image(systemName: "music.note.list")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if deviceSyncManager.syncModeEnabled && deviceSyncManager.hasActiveRemotePlayback {
                Button(action: {
                    deviceSyncManager.enqueueOnConnectedDevices([song])
                }) {
                    Label("Queue on Connected Device", systemImage: "text.badge.plus")
                }
            }

            Button(action: {
                startRadio(for: song)
            }) {
                Label("Start Playlist Gen", systemImage: "music.note.list")
            }

            Button(action: {
                downloadRadio(for: song)
            }) {
                Label("Download Playlist Gen", systemImage: "arrow.down.circle")
            }

            if let artistId = song.artistId, let artist = song.artist {
                NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: artist)) {
                    Label("Go to Artist", systemImage: "person.fill")
                }
            }
        }
    }

    private func startRadio(for song: Song) {
        Task {
            do {
                print("🎵 Starting radio for: \(song.title)")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs(id: song.id, count: 100)
                print("📻 getSimilarSongs returned \(similarSongs.count) songs")

                // Fallback 1: Try artist-based radio if no results
                if similarSongs.isEmpty, let artistId = song.artistId {
                    print("📻 Falling back to artist radio for artist ID: \(artistId)")
                    similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: 100)
                    print("📻 getSimilarSongs2 returned \(similarSongs.count) songs")
                }

                // Fallback 2: Try random songs if still empty
                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: 100)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found even with fallbacks, playing original song")
                        AudioPlayer.shared.playSong(song)
                    } else {
                        // Filter out the source song if it appears in results
                        let filteredSongs = similarSongs.filter { $0.id != song.id }

                        // Build queue with source song first, then similar songs
                        var queue = [song]
                        queue.append(contentsOf: filteredSongs)

                        print("✅ Radio queue ready: 1 source song + \(filteredSongs.count) similar songs = \(queue.count) total")
                        AudioPlayer.shared.playGeneratedPlaylist(sourceSong: song, songs: queue)
                        print("📻 Queue after playQueue: \(AudioPlayer.shared.queue.count) songs")
                    }
                }
            } catch {
                print("❌ Failed to start radio: \(error)")
                // Final fallback: just play the song
                await MainActor.run {
                    AudioPlayer.shared.playSong(song)
                }
            }
        }
    }

    private func startRadioFromAlbum(_ album: Album) {
        // Pick the first song from the album to base radio on
        guard let firstSong = album.song.first else { return }
        startRadio(for: firstSong)
    }

    private func downloadRadio(for song: Song) {
        Task {
            do {
                let radioDownloadCount = UserDefaults.standard.integer(forKey: "radioDownloadCount")
                let count = radioDownloadCount > 0 ? radioDownloadCount : 25

                print("📻 Downloading radio for: \(song.title) (count: \(count))")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs(id: song.id, count: count)
                print("📻 getSimilarSongs returned \(similarSongs.count) songs")

                // Fallback 1: Try artist-based radio if no results
                if similarSongs.isEmpty, let artistId = song.artistId {
                    print("📻 Falling back to artist radio for artist ID: \(artistId)")
                    similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: count)
                    print("📻 getSimilarSongs2 returned \(similarSongs.count) songs")
                }

                // Fallback 2: Try random songs if still empty
                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: count)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found to download for radio")
                    } else {
                        // Filter out the source song if it appears in results
                        let filteredSongs = similarSongs.filter { $0.id != song.id }

                        // Build queue with source song first, then similar songs
                        var queue = [song]
                        queue.append(contentsOf: filteredSongs)

                        print("✅ Downloading radio: \(queue.count) songs")

                        // Download all songs in the radio queue
                        for radioSong in queue {
                            DownloadManager.shared.downloadSong(radioSong)
                        }

                        // Save radio playlist metadata
                        DownloadManager.shared.saveRadioPlaylist(sourceSong: song, songs: queue)
                    }
                }
            } catch {
                print("❌ Failed to download radio: \(error)")
            }
        }
    }

    private func downloadRadioFromAlbum(_ album: Album) {
        guard let firstSong = album.song.first else { return }
        downloadRadio(for: firstSong)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

struct AlbumDetailView: View {
    let albumId: String

    @State private var album: Album?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @AppStorage("offlineMode") private var offlineMode = false

    private var player: AudioPlayer { AudioPlayer.shared }
    private var downloadManager: DownloadManager { DownloadManager.shared }

    var body: some View {
        let _ = print("🔄 AlbumDetailView body recomputed for album: \(albumId)")
        return ZStack {
            if offlineMode {
                // Offline mode: build album from downloaded songs using songMetadata
                let downloadedSongs = downloadManager.songMetadata.values.filter { song in
                    downloadManager.isDownloaded(song.id) && song.albumId == albumId
                }
                if downloadedSongs.isEmpty {
                    VStack {
                        Text("Error")
                            .font(.headline)
                        Text("No downloaded songs for this album")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else {
                    let sortedSongs = downloadedSongs.sorted { ($0.track ?? 999) < ($1.track ?? 999) }
                    ScrollView {
                        VStack(spacing: 12) {
                            Group {
                                if let coverArtId = sortedSongs.first?.coverArt,
                                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                                    CachedAsyncImage(url: coverURL) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    }
                                    .frame(height: 120)
                                    .cornerRadius(8)
                                }
                            }
                            .id(albumId)

                            VStack(spacing: 4) {
                                Text(sortedSongs.first?.album ?? "Unknown Album")
                                    .font(.headline)
                                if let artist = sortedSongs.first?.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Button(action: {
                                    player.playQueue(Array(sortedSongs), startingAt: 0)
                                }) {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)

                                Button(action: {
                                    player.playQueueShuffled(Array(sortedSongs))
                                }) {
                                    Image(systemName: "shuffle")
                                }
                                .buttonStyle(.bordered)
                            }

                            Divider()

                            VStack(spacing: 8) {
                                ForEach(Array(sortedSongs.enumerated()), id: \.element.id) { index, song in
                                    TrackRowView(song: song) {
                                        player.playQueue(Array(sortedSongs), startingAt: index)
                                    }
                                    .id(song.id)
                                }
                            }
                        }
                        .padding()
                    }
                }
            } else if isLoading {
                ProgressView("Loading album...")
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadAlbum()
                    }
                }
            } else if let album = album {
                ScrollView {
                    VStack(spacing: 12) {
                        Group {
                            if let coverArtId = album.coverArt,
                               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 300) {
                                CachedAsyncImage(url: coverURL) { image in
                                    let _ = print("🖼️ AlbumDetail CachedAsyncImage rendering image for album: \(album.id)")
                                    return image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                                .frame(height: 120)
                                .cornerRadius(8)
                                .onAppear {
                                    print("✅ AlbumDetail CachedAsyncImage appeared for album: \(album.id), URL: \(coverURL)")
                                }
                                .onDisappear {
                                    print("❌ AlbumDetail CachedAsyncImage disappeared for album: \(album.id)")
                                }
                            }
                        }
                        .id(album.id)

                        VStack(spacing: 4) {
                            Text(album.name)
                                .font(.headline)
                            if let artist = album.artist, let artistId = album.artistId {
                                NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: artist)) {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            } else if let artist = album.artist {
                                Text(artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let year = album.year {
                                Text(String(year))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                player.playQueue(album.song, startingAt: 0)
                            }) {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button(action: {
                                player.playQueueShuffled(album.song)
                            }) {
                                Image(systemName: "shuffle")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let firstSong = album.song.first {
                            NavigationLink(destination: RadioOptionsView(
                                sourceSong: firstSong,
                                sourceTitle: album.name,
                                sourceType: .album
                            )) {
                                Label("Playlist Gen", systemImage: "music.note.list")
                            }
                            .buttonStyle(.bordered)
                        }

                        AlbumDownloadButton(album: album)

                        Divider()

                        VStack(spacing: 8) {
                            ForEach(Array(filteredSongs(album.song).enumerated()), id: \.element.id) { index, song in
                                TrackRowView(song: song) {
                                    player.playQueue(album.song, startingAt: index)
                                }
                                .id(song.id)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Album")
        .onAppear {
            if !offlineMode {
                loadAlbum()
            }
        }
    }

    private func loadAlbum() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedAlbum = try await NavidromeAPI.shared.getAlbum(id: albumId)
                await MainActor.run {
                    self.album = fetchedAlbum
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

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func isAlbumDownloaded(_ album: Album) -> Bool {
        return album.song.allSatisfy { downloadManager.isDownloaded($0.id) }
    }

    private func isAlbumDownloading(_ album: Album) -> Bool {
        return album.song.contains { downloadManager.isDownloading($0.id) }
    }

    private func filteredSongs(_ songs: [Song]) -> [Song] {
        if offlineMode {
            return songs.filter { downloadManager.isDownloaded($0.id) }
        }
        return songs
    }

    private func startRadio(for song: Song) {
        Task {
            do {
                print("🎵 Starting radio for: \(song.title)")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs(id: song.id, count: 100)
                print("📻 getSimilarSongs returned \(similarSongs.count) songs")

                // Fallback 1: Try artist-based radio if no results
                if similarSongs.isEmpty, let artistId = song.artistId {
                    print("📻 Falling back to artist radio for artist ID: \(artistId)")
                    similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: 100)
                    print("📻 getSimilarSongs2 returned \(similarSongs.count) songs")
                }

                // Fallback 2: Try random songs if still empty
                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: 100)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found even with fallbacks, playing original song")
                        AudioPlayer.shared.playSong(song)
                    } else {
                        // Filter out the source song if it appears in results
                        let filteredSongs = similarSongs.filter { $0.id != song.id }

                        // Build queue with source song first, then similar songs
                        var queue = [song]
                        queue.append(contentsOf: filteredSongs)

                        print("✅ Radio queue ready: 1 source song + \(filteredSongs.count) similar songs = \(queue.count) total")
                        AudioPlayer.shared.playGeneratedPlaylist(sourceSong: song, songs: queue)
                        print("📻 Queue after playQueue: \(AudioPlayer.shared.queue.count) songs")
                    }
                }
            } catch {
                print("❌ Failed to start radio: \(error)")
                // Final fallback: just play the song
                await MainActor.run {
                    AudioPlayer.shared.playSong(song)
                }
            }
        }
    }

    private func startRadioFromAlbum(_ album: Album) {
        // Pick the first song from the album to base radio on
        guard let firstSong = album.song.first else { return }
        startRadio(for: firstSong)
    }

    private func downloadRadioFromAlbum(_ album: Album) {
        guard let firstSong = album.song.first else { return }
        downloadRadio(for: firstSong)
    }

    private func downloadRadio(for song: Song) {
        Task {
            do {
                let radioDownloadCount = UserDefaults.standard.integer(forKey: "radioDownloadCount")
                let count = radioDownloadCount > 0 ? radioDownloadCount : 25

                print("📻 Downloading radio for: \(song.title) (count: \(count))")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongs(id: song.id, count: count)
                print("📻 getSimilarSongs returned \(similarSongs.count) songs")

                // Fallback 1: Try artist-based radio if no results
                if similarSongs.isEmpty, let artistId = song.artistId {
                    print("📻 Falling back to artist radio for artist ID: \(artistId)")
                    similarSongs = try await NavidromeAPI.shared.getSimilarSongs2(artistId: artistId, count: count)
                    print("📻 getSimilarSongs2 returned \(similarSongs.count) songs")
                }

                // Fallback 2: Try random songs if still empty
                if similarSongs.isEmpty {
                    print("📻 Falling back to random songs")
                    similarSongs = try await NavidromeAPI.shared.getRandomSongs(size: count)
                    print("📻 getRandomSongs returned \(similarSongs.count) songs")
                }

                await MainActor.run {
                    if similarSongs.isEmpty {
                        print("⚠️ No songs found to download for radio")
                    } else {
                        // Filter out the source song if it appears in results
                        let filteredSongs = similarSongs.filter { $0.id != song.id }

                        // Build queue with source song first, then similar songs
                        var queue = [song]
                        queue.append(contentsOf: filteredSongs)

                        print("✅ Downloading radio: \(queue.count) songs")

                        // Download all songs in the radio queue
                        for radioSong in queue {
                            DownloadManager.shared.downloadSong(radioSong)
                        }

                        // Save radio playlist metadata
                        DownloadManager.shared.saveRadioPlaylist(sourceSong: song, songs: queue)
                    }
                }
            } catch {
                print("❌ Failed to download radio: \(error)")
            }
        }
    }
}

// Separate component that observes download manager
struct AlbumDownloadButton: View {
    let album: Album
    @ObservedObject var downloadManager = DownloadManager.shared

    var body: some View {
        HStack(spacing: 8) {
            if isAlbumDownloaded() {
                Button(action: {
                    downloadManager.deleteAlbum(album)
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else if isAlbumDownloading() {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Downloading")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(true)
            } else {
                Button(action: {
                    downloadManager.downloadAlbum(album)
                }) {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func isAlbumDownloaded() -> Bool {
        return album.song.allSatisfy { downloadManager.isDownloaded($0.id) }
    }

    private func isAlbumDownloading() -> Bool {
        return album.song.contains { downloadManager.isDownloading($0.id) }
    }
}
