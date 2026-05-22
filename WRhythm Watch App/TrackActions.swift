//
//  TrackActions.swift
//  WRhythm
//
//  Shared actions for track rows and context menus.
//

import SwiftUI

@MainActor
enum TrackActions {
    static func addToQueue(_ song: Song) {
        Task { @MainActor in
            AudioPlayer.shared.enqueue([song])
        }
    }

    static func addAlbumToQueue(albumId: String, albumName: String? = nil) {
        Task {
            let localSongs = downloadedSongsForAlbum(albumId)
            if UserDefaults.standard.bool(forKey: "offlineMode"), !localSongs.isEmpty {
                await MainActor.run {
                    AudioPlayer.shared.enqueue(localSongs)
                }
                return
            }

            do {
                let album = try await NavidromeAPI.shared.getAlbum(id: albumId)
                await MainActor.run {
                    AudioPlayer.shared.enqueue(album.song.sortedByTrack())
                }
            } catch {
                if !localSongs.isEmpty {
                    await MainActor.run {
                        AudioPlayer.shared.enqueue(localSongs)
                    }
                    return
                }
                print("❌ Failed to add album to queue: \(albumName ?? albumId) - \(error)")
            }
        }
    }

    static func addPlaylistToQueue(playlistId: String, playlistName: String? = nil) {
        Task {
            var localSongs: [Song] = []
            if let cachedPlaylist = DownloadManager.shared.cachedPlaylists.first(where: { $0.id == playlistId }) {
                localSongs = cachedPlaylist.songIds.compactMap { songId -> Song? in
                    let manager = DownloadManager.shared
                    guard manager.isDownloaded(songId) else { return nil }
                    return manager.songMetadata[songId]
                }

                if UserDefaults.standard.bool(forKey: "offlineMode"), !localSongs.isEmpty {
                    let songsToQueue = localSongs
                    await MainActor.run {
                        AudioPlayer.shared.enqueue(songsToQueue)
                    }
                    return
                }
            }

            do {
                let playlist = try await NavidromeAPI.shared.getPlaylist(id: playlistId)
                await MainActor.run {
                    AudioPlayer.shared.enqueue(playlist.entry ?? [])
                }
            } catch {
                if !localSongs.isEmpty {
                    let songsToQueue = localSongs
                    await MainActor.run {
                        AudioPlayer.shared.enqueue(songsToQueue)
                    }
                    return
                }
                print("❌ Failed to add playlist to queue: \(playlistName ?? playlistId) - \(error)")
            }
        }
    }

    static func addArtistToQueue(artistId: String, artistName: String) {
        Task {
            let localSongs = downloadedSongsForArtist(artistName)
            if (artistId.hasPrefix("offline-") || UserDefaults.standard.bool(forKey: "offlineMode")), !localSongs.isEmpty {
                await MainActor.run {
                    AudioPlayer.shared.enqueue(localSongs)
                }
                return
            }

            do {
                let artist = try await NavidromeAPI.shared.getArtist(id: artistId)
                var songs: [Song] = []

                for album in artist.album {
                    do {
                        let fullAlbum = try await NavidromeAPI.shared.getAlbum(id: album.id)
                        songs.append(contentsOf: fullAlbum.song.sortedByTrack())
                    } catch {
                        print("❌ Failed to fetch album for artist queue: \(album.name) - \(error)")
                    }
                }

                let songsToQueue = songs
                await MainActor.run {
                    AudioPlayer.shared.enqueue(songsToQueue)
                }
            } catch {
                if !localSongs.isEmpty {
                    await MainActor.run {
                        AudioPlayer.shared.enqueue(localSongs)
                    }
                    return
                }
                print("❌ Failed to add artist to queue: \(artistName) - \(error)")
            }
        }
    }

    static func toggleFavorite(_ song: Song) {
        let isStarred = DownloadManager.shared.starredSongIds.contains(song.id)

        Task {
            do {
                if isStarred {
                    try await NavidromeAPI.shared.unstar(songId: song.id)
                    await MainActor.run {
                        DownloadManager.shared.unstarSong(song.id, isOffline: false)
                    }
                } else {
                    try await NavidromeAPI.shared.star(songId: song.id)
                    await MainActor.run {
                        DownloadManager.shared.starSong(song.id, isOffline: false)
                    }
                }
            } catch {
                print("❌ Failed to toggle favorite: \(error)")
            }
        }
    }

    static func startRadio(for song: Song) {
        Task {
            do {
                let savedCount = UserDefaults.standard.integer(forKey: "radioDownloadCount")
                let count = savedCount > 0 ? savedCount : 25

                let similarSongs = try await NavidromeAPI.shared.getSimilarSongsForSong(song, count: count)

                let filteredSongs = similarSongs.filter { $0.id != song.id }
                await MainActor.run {
                    AudioPlayer.shared.playGeneratedPlaylist(sourceSong: song, songs: [song] + filteredSongs)
                }
            } catch {
                print("❌ Failed to start radio: \(error)")
            }
        }
    }

    private static func downloadedSongsForAlbum(_ albumId: String) -> [Song] {
        let manager = DownloadManager.shared
        return manager.songMetadata.values
            .filter { $0.albumId == albumId && manager.isDownloaded($0.id) }
            .sortedByTrack()
    }

    private static func downloadedSongsForArtist(_ artistName: String) -> [Song] {
        let manager = DownloadManager.shared
        return manager.songMetadata.values
            .filter { $0.artist == artistName && manager.isDownloaded($0.id) }
            .sorted {
                if ($0.album ?? "") != ($1.album ?? "") {
                    return ($0.album ?? "") < ($1.album ?? "")
                }
                if ($0.track ?? Int.max) != ($1.track ?? Int.max) {
                    return ($0.track ?? Int.max) < ($1.track ?? Int.max)
                }
                return $0.title < $1.title
            }
    }
}

struct TrackContextMenuItems: View {
    let song: Song
    @ObservedObject var player = AudioPlayer.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        Button(action: {
            player.playSong(song)
        }) {
            Label("Play", systemImage: "play.fill")
        }

        Button(action: {
            TrackActions.addToQueue(song)
        }) {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }

        if !offlineMode {
            Button(action: {
                TrackActions.toggleFavorite(song)
            }) {
                Label(
                    downloadManager.starredSongIds.contains(song.id) ? "Unfavorite" : "Favorite",
                    systemImage: downloadManager.starredSongIds.contains(song.id) ? "heart.fill" : "heart"
                )
            }

            Button(action: {
                TrackActions.startRadio(for: song)
            }) {
                Label("Start Playlist Gen", systemImage: "music.note.list")
            }

            if downloadManager.isDownloaded(song.id) {
                Button(role: .destructive, action: {
                    downloadManager.deleteSong(song.id)
                }) {
                    Label("Delete Download", systemImage: "trash")
                }
            } else {
                Button(action: {
                    downloadManager.downloadSong(song)
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }

        if deviceSyncManager.syncModeEnabled && deviceSyncManager.hasActiveRemotePlayback {
            Button(action: {
                deviceSyncManager.enqueueOnConnectedDevices([song])
            }) {
                Label("Queue on Connected Device", systemImage: "text.badge.plus")
            }
        }

        if let artistId = song.artistId, let artist = song.artist {
            NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: artist)) {
                Label("Go to Artist", systemImage: "person.fill")
            }
        }

        if let albumId = song.albumId {
            NavigationLink(destination: AlbumDetailView(albumId: albumId)) {
                Label("Go to Album", systemImage: "square.stack")
            }
        }
    }
}

struct AlbumContextMenuItems: View {
    let albumId: String
    let albumName: String?

    var body: some View {
        Button(action: {
            TrackActions.addAlbumToQueue(albumId: albumId, albumName: albumName)
        }) {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }

        NavigationLink(destination: AlbumDetailView(albumId: albumId)) {
            Label("Go to Album", systemImage: "square.stack")
        }
    }
}

struct PlaylistContextMenuItems: View {
    let playlistId: String
    let playlistName: String?

    var body: some View {
        Button(action: {
            TrackActions.addPlaylistToQueue(playlistId: playlistId, playlistName: playlistName)
        }) {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }

        NavigationLink(destination: PlaylistDetailView(playlistId: playlistId, playlistName: playlistName ?? "Playlist")) {
            Label("Go to Playlist", systemImage: "music.note.list")
        }
    }
}

struct ArtistContextMenuItems: View {
    let artistId: String
    let artistName: String

    var body: some View {
        Button(action: {
            TrackActions.addArtistToQueue(artistId: artistId, artistName: artistName)
        }) {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }

        NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: artistName)) {
            Label("Go to Artist", systemImage: "person.fill")
        }
    }
}

extension View {
    func wrhythmTrackActions(song: Song) -> some View {
        modifier(WRhythmTrackActionsModifier(song: song))
    }

    func wrhythmAlbumActions(albumId: String, albumName: String?) -> some View {
        modifier(WRhythmAlbumActionsModifier(albumId: albumId, albumName: albumName))
    }

    func wrhythmPlaylistActions(playlistId: String, playlistName: String?) -> some View {
        modifier(WRhythmPlaylistActionsModifier(playlistId: playlistId, playlistName: playlistName))
    }

    func wrhythmArtistActions(artistId: String, artistName: String) -> some View {
        modifier(WRhythmArtistActionsModifier(artistId: artistId, artistName: artistName))
    }

    func wrhythmAlbumDetailTrackActions(
        song: Song,
        startRadio: @escaping (Song) -> Void,
        downloadRadio: @escaping (Song) -> Void
    ) -> some View {
        modifier(WRhythmAlbumDetailTrackActionsModifier(
            song: song,
            startRadio: startRadio,
            downloadRadio: downloadRadio
        ))
    }
}

private struct WRhythmTrackActionsModifier: ViewModifier {
    let song: Song

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(watchOS)
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                WatchTrackSwipeActions(song: song)
            }
#else
        content
            .contextMenu {
                TrackContextMenuItems(song: song)
            }
#endif
    }
}

private struct WRhythmAlbumActionsModifier: ViewModifier {
    let albumId: String
    let albumName: String?

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(watchOS)
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    TrackActions.addAlbumToQueue(albumId: albumId, albumName: albumName)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
                .tint(WRhythmTheme.accent)
            }
#else
        content
            .contextMenu {
                AlbumContextMenuItems(albumId: albumId, albumName: albumName)
            }
#endif
    }
}

private struct WRhythmPlaylistActionsModifier: ViewModifier {
    let playlistId: String
    let playlistName: String?

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(watchOS)
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    TrackActions.addPlaylistToQueue(playlistId: playlistId, playlistName: playlistName)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
                .tint(WRhythmTheme.accent)
            }
#else
        content
            .contextMenu {
                PlaylistContextMenuItems(playlistId: playlistId, playlistName: playlistName)
            }
#endif
    }
}

private struct WRhythmArtistActionsModifier: ViewModifier {
    let artistId: String
    let artistName: String

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(watchOS)
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    TrackActions.addArtistToQueue(artistId: artistId, artistName: artistName)
                } label: {
                    Label("Add to Queue", systemImage: "text.badge.plus")
                }
                .tint(WRhythmTheme.accent)
            }
#else
        content
            .contextMenu {
                ArtistContextMenuItems(artistId: artistId, artistName: artistName)
            }
#endif
    }
}

private struct WRhythmAlbumDetailTrackActionsModifier: ViewModifier {
    let song: Song
    let startRadio: (Song) -> Void
    let downloadRadio: (Song) -> Void
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(watchOS)
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if deviceSyncManager.syncModeEnabled && deviceSyncManager.hasActiveRemotePlayback {
                    Button {
                        deviceSyncManager.enqueueOnConnectedDevices([song])
                    } label: {
                        Label("Queue on Connected Device", systemImage: "display.and.arrow.down")
                    }
                    .tint(WRhythmTheme.warning)
                }

                Button {
                    startRadio(song)
                } label: {
                    Label("Start Playlist Gen", systemImage: "music.note.list")
                }
                .tint(WRhythmTheme.accent)

                Button {
                    downloadRadio(song)
                } label: {
                    Label("Download Playlist Gen", systemImage: "arrow.down.circle")
                }
                .tint(WRhythmTheme.success)
            }
#else
        content
            .contextMenu {
                if deviceSyncManager.syncModeEnabled && deviceSyncManager.hasActiveRemotePlayback {
                    Button {
                        deviceSyncManager.enqueueOnConnectedDevices([song])
                    } label: {
                        Label("Queue on Connected Device", systemImage: "text.badge.plus")
                    }
                }

                Button {
                    startRadio(song)
                } label: {
                    Label("Start Playlist Gen", systemImage: "music.note.list")
                }

                Button {
                    downloadRadio(song)
                } label: {
                    Label("Download Playlist Gen", systemImage: "arrow.down.circle")
                }

                if let artistId = song.artistId, let artist = song.artist {
                    NavigationLink(destination: ArtistDetailView(artistId: artistId, artistName: artist)) {
                        Label("Go to Artist", systemImage: "person.fill")
                    }
                }
            }
#endif
    }
}

#if os(watchOS)
private struct WatchTrackSwipeActions: View {
    let song: Song
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var deviceSyncManager = DeviceSyncManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    var body: some View {
        Button {
            TrackActions.addToQueue(song)
        } label: {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        .tint(WRhythmTheme.accent)

        if !offlineMode {
            Button {
                TrackActions.toggleFavorite(song)
            } label: {
                Label(
                    downloadManager.starredSongIds.contains(song.id) ? "Unfavorite" : "Favorite",
                    systemImage: downloadManager.starredSongIds.contains(song.id) ? "heart.fill" : "heart"
            )
        }
            .tint(WRhythmTheme.favorite)

            Button {
                TrackActions.startRadio(for: song)
            } label: {
                Label("Start Playlist Gen", systemImage: "music.note.list")
            }
            .tint(WRhythmTheme.accent)

            if downloadManager.isDownloaded(song.id) {
                Button(role: .destructive) {
                    downloadManager.deleteSong(song.id)
                } label: {
                    Label("Delete Download", systemImage: "trash")
                }
            } else {
                Button {
                    downloadManager.downloadSong(song)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tint(WRhythmTheme.success)
            }
        }

        if deviceSyncManager.syncModeEnabled && deviceSyncManager.hasActiveRemotePlayback {
            Button {
                deviceSyncManager.enqueueOnConnectedDevices([song])
            } label: {
                Label("Queue on Connected Device", systemImage: "display.and.arrow.down")
            }
            .tint(WRhythmTheme.warning)
        }
    }
}
#endif

private extension Array where Element == Song {
    func sortedByTrack() -> [Song] {
        sorted {
            if ($0.track ?? Int.max) != ($1.track ?? Int.max) {
                return ($0.track ?? Int.max) < ($1.track ?? Int.max)
            }
            return $0.title < $1.title
        }
    }
}
