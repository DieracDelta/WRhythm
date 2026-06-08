//
//  ArtistDetailView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

nonisolated struct ArtistDetailStatePolicy: Sendable {
    static func shouldResetDisplayedArtist(currentArtistID: String?, requestedArtistID: String) -> Bool {
        guard let currentArtistID else { return false }
        return currentArtistID != requestedArtistID
    }

    static func shouldApplyFetchedArtist(
        fetchedArtistID: String,
        requestedArtistID: String,
        activeArtistID: String
    ) -> Bool {
        // Some Subsonic-compatible servers echo a display-name ID from getArtist.
        // Stale response protection should depend on the route we requested, not
        // the server's echoed artist identifier.
        requestedArtistID == activeArtistID
    }
}

struct ArtistDetailView: View {
    let artistId: String
    let artistName: String

    @State private var artist: ArtistWithAlbums?
    @State private var similarArtists: [Artist] = []
    @State private var isLoadingSimilarArtists = false
    @State private var isLoading = true
    @State private var errorMessage = ""
    @ObservedObject private var api = NavidromeAPI.shared
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false
    @AppStorage("experimentalAudioMuseFeaturesEnabled") private var experimentalAudioMuseFeaturesEnabled = false

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
        .task(id: "\(artistId)-\(offlineMode)") {
            if !offlineMode {
                await loadArtist(for: artistId)
            }
        }
        .task(id: "\(artistId)-\(experimentalAudioMuseFeaturesEnabled)-\(offlineMode)") {
            await loadSimilarArtistsIfAvailable()
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
#if os(iOS)
        phoneArtistContent(
            title: artistName,
            subtitle: "\(albums.count) downloaded album\(albums.count == 1 ? "" : "s")",
            detail: "Offline artist",
            coverArtId: albums.first?.coverArt,
            albumsAreEmpty: albums.isEmpty,
            playAction: { playAllDownloadedSongs(for: artistName) },
            shuffleAction: { shuffleAllDownloadedSongs(for: artistName) },
            trailingAction: {
                EmptyView()
            }
        ) {
            if albums.isEmpty {
                WRhythmEmptyState(
                    systemImage: "arrow.down.circle",
                    title: "No downloaded albums",
                    message: "Download music while online to access this artist offline"
                )
            } else {
                albumSection(albums: albums, mode: "offline")
            }
        }
#else
        WRhythmScreen(coverArtId: albums.first?.coverArt) {
            WRhythmHeroHeader(
                title: artistName,
                subtitle: "\(albums.count) downloaded album\(albums.count == 1 ? "" : "s")",
                detail: "Offline artist",
                systemImage: "person.fill",
                tint: WRhythmTheme.artist,
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
                albumSection(albums: albums, mode: "offline")
            }
        }
#endif
    }

    @ViewBuilder
    private func onlineArtistContent(_ artist: ArtistWithAlbums) -> some View {
        let albums = filteredAlbums(artist.album)
#if os(iOS)
        phoneArtistContent(
            title: artistName,
            subtitle: "\(albums.count) album\(albums.count == 1 ? "" : "s")",
            detail: "Artist",
            coverArtId: artist.coverArt ?? albums.first?.coverArt,
            albumsAreEmpty: albums.isEmpty,
            playAction: { playAllSongs(artist) },
            shuffleAction: { shuffleAllSongs(artist) },
            trailingAction: {
                if isArtistDownloaded(artist) {
                    Button(action: {
                        deleteArtist(artist)
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(WRhythmTheme.danger)
                } else {
                    Button(action: {
                        downloadArtist(artist)
                    }) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
            }
        ) {
            similarArtistsSection()
            albumSection(albums: albums, mode: "online")
        }
#else
        WRhythmScreen(coverArtId: albums.first?.coverArt) {
            WRhythmHeroHeader(
                title: artistName,
                subtitle: "\(albums.count) album\(albums.count == 1 ? "" : "s")",
                detail: "Artist",
                systemImage: "person.fill",
                tint: WRhythmTheme.artist,
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
                        .tint(WRhythmTheme.danger)
                    } else {
                        Button(action: {
                            downloadArtist(artist)
                        }) {
                            Image(systemName: "arrow.down.circle")
                        }
                    }
                }
            }

            similarArtistsSection()

            albumSection(albums: albums, mode: "online")
        }
#endif
    }

#if os(iOS)
    private func phoneArtistContent<BodyContent: View, TrailingAction: View>(
        title: String,
        subtitle: String,
        detail: String,
        coverArtId: String?,
        albumsAreEmpty: Bool,
        playAction: @escaping () -> Void,
        shuffleAction: @escaping () -> Void,
        @ViewBuilder trailingAction: () -> TrailingAction,
        @ViewBuilder bodyContent: () -> BodyContent
    ) -> some View {
        WRhythmScreen(coverArtId: coverArtId, contentMaxWidth: 760) {
            WRhythmCard(style: .glass) {
                VStack(alignment: .leading, spacing: WRhythmSpacing.md) {
                    HStack(alignment: .center, spacing: WRhythmSpacing.md) {
                        WRhythmArtworkThumbnail(
                            coverArtId: coverArtId,
                            fallbackSystemImage: "person.fill",
                            tint: WRhythmTheme.artist,
                            size: 58
                        )

                        VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                            Text(title)
                                .font(WRhythmTypography.featureTitle)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(subtitle)
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(detail)
                                .font(WRhythmTypography.metadata)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }

                    ViewThatFits(in: .horizontal) {
                        artistActionRow(
                            albumsAreEmpty: albumsAreEmpty,
                            playAction: playAction,
                            shuffleAction: shuffleAction,
                            trailingAction: trailingAction
                        )

                        artistActionColumn(
                            albumsAreEmpty: albumsAreEmpty,
                            playAction: playAction,
                            shuffleAction: shuffleAction,
                            trailingAction: trailingAction
                        )
                    }
                }
            }

            bodyContent()
        }
    }

    private func artistActionRow<TrailingAction: View>(
        albumsAreEmpty: Bool,
        playAction: @escaping () -> Void,
        shuffleAction: @escaping () -> Void,
        @ViewBuilder trailingAction: () -> TrailingAction
    ) -> some View {
        HStack(spacing: WRhythmSpacing.xs) {
            artistActionButtons(
                albumsAreEmpty: albumsAreEmpty,
                playAction: playAction,
                shuffleAction: shuffleAction,
                trailingAction: trailingAction
            )
        }
        .buttonStyle(.bordered)
    }

    private func artistActionColumn<TrailingAction: View>(
        albumsAreEmpty: Bool,
        playAction: @escaping () -> Void,
        shuffleAction: @escaping () -> Void,
        @ViewBuilder trailingAction: () -> TrailingAction
    ) -> some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            artistActionButtons(
                albumsAreEmpty: albumsAreEmpty,
                playAction: playAction,
                shuffleAction: shuffleAction,
                trailingAction: trailingAction
            )
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func artistActionButtons<TrailingAction: View>(
        albumsAreEmpty: Bool,
        playAction: @escaping () -> Void,
        shuffleAction: @escaping () -> Void,
        @ViewBuilder trailingAction: () -> TrailingAction
    ) -> some View {
        Button(action: playAction) {
            Label("Play All", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(albumsAreEmpty)

        Button(action: shuffleAction) {
            Label("Shuffle", systemImage: "shuffle")
        }
        .disabled(albumsAreEmpty)

        artistRadioLink(label: "Generate")

        trailingAction()
    }
#endif

    @ViewBuilder
    private func similarArtistsSection() -> some View {
        if experimentalAudioMuseFeaturesEnabled && api.audioMuseSimilarArtistsSupported == true && (!similarArtists.isEmpty || isLoadingSimilarArtists) {
            VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                WRhythmSectionHeader(
                    title: "Similar Artists",
                    subtitle: isLoadingSimilarArtists ? "Loading" : "\(similarArtists.count) found"
                )

                WRhythmCard(padding: WRhythmSpacing.sm) {
                    if isLoadingSimilarArtists && similarArtists.isEmpty {
                        HStack(spacing: WRhythmSpacing.sm) {
                            ProgressView()
                            Text("Finding similar artists")
                                .font(WRhythmTypography.rowSubtitle)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, WRhythmSpacing.sm)
                    } else {
                        ForEach(similarArtists.prefix(8)) { artist in
                            NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name).id(artist.id)) {
                                WRhythmCollectionRow(
                                    title: artist.name,
                                    subtitle: artist.albumCount.map { "\($0) albums" },
                                    coverArtId: artist.coverArt,
                                    fallbackSystemImage: "person.2",
                                    tint: WRhythmTheme.playlistGen
                                )
                            }
                            .buttonStyle(.plain)
                            .wrhythmArtistActions(artistId: artist.id, artistName: artist.name)

                            if artist.id != similarArtists.prefix(8).last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func albumSection(albums: [AlbumSummary], mode: String) -> some View {
        let resetToken = SongRenderWindowPolicy.artistAlbumResetToken(artistId: artistId, mode: mode)

        return VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            WRhythmSectionHeader(
                title: "Albums",
                subtitle: "\(albums.count) album\(albums.count == 1 ? "" : "s")"
            )

            WRhythmCard(padding: WRhythmSpacing.sm) {
                SlidingRenderWindowForEach(albums, estimatedRowHeight: 64, resetToken: resetToken) { _, album in
                    NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                        WRhythmCollectionRow(
                            title: album.name,
                            subtitle: album.year.map(String.init),
                            coverArtId: album.coverArt,
                            fallbackSystemImage: "square.stack",
                            tint: WRhythmTheme.album
                        ) {
                            if isAlbumDownloaded(album.id) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(WRhythmTypography.metadata)
                                    .foregroundColor(WRhythmTheme.success)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .wrhythmAlbumActions(albumId: album.id, albumName: album.name)
                }
            }
        }
    }

    private func artistRadioLink(label: String? = nil) -> some View {
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
            if let label {
                Label(label, systemImage: "music.note.list")
            } else {
                Image(systemName: "music.note.list")
            }
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
        let requestedArtistId = artistId
        Task {
            await loadArtist(for: requestedArtistId)
        }
    }

    private func loadArtist(for requestedArtistId: String) async {
        isLoading = true
        errorMessage = ""
        if ArtistDetailStatePolicy.shouldResetDisplayedArtist(
            currentArtistID: artist?.id,
            requestedArtistID: requestedArtistId
        ) {
            artist = nil
        }

        do {
            let fetchedArtist = try await NavidromeAPI.shared.getArtist(id: requestedArtistId)
            await MainActor.run {
                guard ArtistDetailStatePolicy.shouldApplyFetchedArtist(
                    fetchedArtistID: fetchedArtist.id,
                    requestedArtistID: requestedArtistId,
                    activeArtistID: artistId
                ) else {
                    return
                }
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

    private func loadSimilarArtistsIfAvailable() async {
        guard !offlineMode, experimentalAudioMuseFeaturesEnabled else {
            similarArtists = []
            return
        }

        let supported: Bool
        if let cached = api.audioMuseSimilarArtistsSupported {
            supported = cached
        } else {
            supported = await api.checkAudioMuseFeatureSupport(.similarArtists)
        }

        guard supported else {
            similarArtists = []
            return
        }

        isLoadingSimilarArtists = true
        do {
            let fetched = try await api.getSimilarArtists2(artistId: artistId, count: 8)
            guard !Task.isCancelled else { return }
            similarArtists = fetched
        } catch {
            similarArtists = []
        }
        isLoadingSimilarArtists = false
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
