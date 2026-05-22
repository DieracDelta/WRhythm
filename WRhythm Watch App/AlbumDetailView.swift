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
            HStack(spacing: WRhythmSpacing.sm) {
                if let track = song.track {
                    Text("\(track)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 20, alignment: .leading)
                }

                WRhythmArtworkThumbnail(coverArtId: song.coverArt, size: 38)

                VStack(alignment: .leading) {
                    Text(song.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let duration = song.duration {
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if downloadManager.isDownloading(song.id) {
                    VStack(spacing: WRhythmSpacing.xxs) {
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
                        .foregroundColor(WRhythmTheme.success)
                }

                if player.currentSong?.id == song.id && player.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundColor(WRhythmTheme.accent)
                }

                NavigationLink(destination: RadioOptionsView(
                    sourceSong: song,
                    sourceTitle: song.title,
                    sourceType: .song
                )) {
                    Image(systemName: "music.note.list")
                        .font(.caption2)
                        .foregroundColor(WRhythmTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(WRhythmSpacing.xs)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .wrhythmAlbumDetailTrackActions(song: song, startRadio: startRadio(for:), downloadRadio: downloadRadio(for:))
    }

    private func startRadio(for song: Song) {
        Task {
            do {
                print("🎵 Starting radio for: \(song.title)")
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(song, count: 100)
                print("📻 ID3 similar songs returned \(similarSongs.count) songs")

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
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(song, count: count)
                print("📻 ID3 similar songs returned \(similarSongs.count) songs")

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
    @ObservedObject private var player = AudioPlayer.shared
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        content
        .navigationTitle("Album")
        .onAppear {
            if !offlineMode {
                loadAlbum()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if offlineMode {
            offlineAlbumContent
        } else if isLoading {
            WRhythmLoadingState(
                systemImage: "square.stack",
                title: "Loading album",
                message: nil
            )
            .wrhythmPageBackground()
        } else if !errorMessage.isEmpty {
            WRhythmErrorState(
                title: "Album Error",
                message: errorMessage
            ) {
                loadAlbum()
            }
            .wrhythmPageBackground()
        } else if let album {
            onlineAlbumContent(album)
        }
    }

    @ViewBuilder
    private var offlineAlbumContent: some View {
        let songs = offlineAlbumSongs
        if songs.isEmpty {
            WRhythmErrorState(
                title: "Album unavailable offline",
                message: "No downloaded songs were found for this album.",
                actionTitle: "Retry"
            ) {}
            .wrhythmPageBackground()
        } else {
            WRhythmScreen(coverArtId: songs.first?.coverArt) {
                WRhythmHeroHeader(
                    title: songs.first?.album ?? "Unknown Album",
                    subtitle: songs.first?.artist,
                    detail: "\(songs.count) downloaded song\(songs.count == 1 ? "" : "s")",
                    systemImage: "square.stack",
                    tint: WRhythmTheme.album,
                    coverArtId: songs.first?.coverArt
                ) {
                    WRhythmActionStrip {
                        Button(action: {
                            player.playQueue(songs, startingAt: 0)
                        }) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button(action: {
                            player.playQueueShuffled(songs)
                        }) {
                            Image(systemName: "shuffle")
                        }
                    }
                }

                trackSection(songs: songs, queue: songs)
            }
        }
    }

    private func onlineAlbumContent(_ album: Album) -> some View {
        WRhythmScreen(coverArtId: album.coverArt) {
            WRhythmHeroHeader(
                title: album.name,
                subtitle: album.artist,
                detail: albumDetailText(album),
                systemImage: "square.stack",
                tint: WRhythmTheme.album,
                coverArtId: album.coverArt
            ) {
                WRhythmActionStrip {
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

                    if let firstSong = album.song.first {
                        NavigationLink(destination: RadioOptionsView(
                            sourceSong: firstSong,
                            sourceTitle: album.name,
                            sourceType: .album
                        )) {
                            Image(systemName: "music.note.list")
                        }
                    }

                    AlbumDownloadButton(album: album)
                }
            }

            if let artist = album.artist, let artistId = album.artistId {
                NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: artist)) {
                    WRhythmCard(padding: 12) {
                        WRhythmCollectionRow(
                            title: artist,
                            subtitle: "Artist",
                            coverArtId: album.coverArt,
                            fallbackSystemImage: "person.fill",
                            tint: WRhythmTheme.artist
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            trackSection(songs: filteredSongs(album.song), queue: album.song)
        }
    }

    private var offlineAlbumSongs: [Song] {
        downloadManager.songMetadata.values
            .filter { song in
                downloadManager.isDownloaded(song.id) && song.albumId == albumId
            }
            .sorted { ($0.track ?? 999) < ($1.track ?? 999) }
    }

    private func albumDetailText(_ album: Album) -> String {
        var parts = ["\(album.song.count) song\(album.song.count == 1 ? "" : "s")"]
        if let year = album.year {
            parts.append(String(year))
        }
        return parts.joined(separator: " - ")
    }

    private func trackSection(songs: [Song], queue: [Song]) -> some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            WRhythmSectionHeader(
                title: "Tracks",
                subtitle: "\(songs.count) song\(songs.count == 1 ? "" : "s")"
            )

            WRhythmCard(padding: WRhythmSpacing.sm) {
                VStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: offlineMode) {
                            player.playQueue(queue, startingAt: index)
                        }
                    }
                }
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
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(song, count: 100)
                print("📻 ID3 similar songs returned \(similarSongs.count) songs")

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
                var similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(song, count: count)
                print("📻 ID3 similar songs returned \(similarSongs.count) songs")

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
                .tint(WRhythmTheme.danger)
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
