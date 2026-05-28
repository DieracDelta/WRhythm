//
//  FavouritesView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct FavouritesView: View {
    @EnvironmentObject var libraryDataManager: LibraryDataManager
    @State private var searchText = ""
    @State private var songSortOption: SongSortOption = .original
    @State private var albumSortOption: AlbumSortOption = .titleAscending
    @State private var artistSortOption: ArtistSortOption = .nameAscending
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var player = AudioPlayer.shared
    @AppStorage("offlineMode") private var offlineMode = false

    // Get starred songs from downloaded songs in offline mode
    private var offlineStarredSongs: [Song] {
        downloadManager.starredSongIds.compactMap { songId in
            downloadManager.songMetadata[songId]
        }.filter { song in
            downloadManager.isDownloaded(song.id)
        }
    }

    private func filteredSongs(_ songs: [Song]) -> [Song] {
        var filtered = songs
        if offlineMode {
            filtered = filtered.filter { downloadManager.isDownloaded($0.id) }
        }
        guard !searchText.isEmpty else {
            return filtered
        }
        return filtered.filter { song in
            song.title.localizedCaseInsensitiveContains(searchText) ||
            (song.artist?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (song.album?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func filteredAlbums(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        var filtered = albums
        if offlineMode {
            filtered = filtered.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
        }
        guard !searchText.isEmpty else {
            return filtered
        }
        return filtered.filter { album in
            album.name.localizedCaseInsensitiveContains(searchText) ||
            (album.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func filteredArtists(_ artists: [Artist]) -> [Artist] {
        var filtered = artists
        if offlineMode {
            filtered = filtered.filter { artist in
                downloadManager.downloadedSongs.values.contains { song in
                    song.artist == artist.name
                }
            }
        }
        guard !searchText.isEmpty else {
            return filtered
        }
        return filtered.filter { artist in
            artist.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
#if os(iOS)
            VStack(spacing: 0) {
                PhoneDetailHeader(title: "Favourites")
                    .padding(.horizontal, WRhythmSpacing.md)
                    .padding(.top, WRhythmSpacing.xxl)
                    .padding(.bottom, WRhythmSpacing.xs)

                inlineSearchField
                    .padding(.horizontal, WRhythmSpacing.md)
                    .padding(.bottom, WRhythmSpacing.sm)

                content
            }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
#else
            content
                .navigationTitle("Favourites")
#endif
        }
        .wrhythmPageBackground()
        .onAppear {
            if !offlineMode && libraryDataManager.starred == nil && !libraryDataManager.isLoadingStarred {
                libraryDataManager.fetchStarred()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if offlineMode {
            offlineContent
        } else {
            onlineContent
        }
    }

    @ViewBuilder
    private var offlineContent: some View {
        // Offline mode: show starred songs from local cache
        if offlineStarredSongs.isEmpty {
            WRhythmEmptyState(
                systemImage: "star",
                title: "No favourites available offline",
                message: "Star and download songs while online to see them here"
            )
        } else if filteredSongs(offlineStarredSongs).isEmpty {
            WRhythmEmptyState(
                systemImage: "magnifyingglass",
                title: "No favourites found",
                message: "Try a different search term"
            )
        } else {
            let songsToShow = songSortOption.sorted(filteredSongs(offlineStarredSongs))
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Songs")
                                .font(WRhythmTypography.featureTitle)
                            Spacer()
                            WRhythmSortMenu(selection: $songSortOption)
                            if songsToShow.count > 1 {
                                HStack(spacing: 8) {
                                    Button(action: {
                                        player.playQueue(songsToShow, startingAt: 0)
                                    }) {
                                        Image(systemName: "play.fill")
                                            .font(WRhythmTypography.rowSubtitle)
                                    }
                                    Button(action: {
                                        player.playQueueShuffled(songsToShow)
                                    }) {
                                        Image(systemName: "shuffle")
                                            .font(WRhythmTypography.rowSubtitle)
                                    }
                                }
                            }
                        }

                        SlidingRenderWindowForEach(songsToShow, estimatedRowHeight: 64, resetToken: songSortOption) { index, song in
                            TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: offlineMode) {
                                player.playQueue(songsToShow, startingAt: index)
                            }
                        }
                    }
                }
                .padding()
#if os(iOS)
                .padding(.top, WRhythmSpacing.md)
                .padding(.bottom, WRhythmVisual.bottomNavigationClearance)
#endif
            }
#if os(iOS)
            .scrollIndicators(.hidden)
#endif
        }
    }

    @ViewBuilder
    private var onlineContent: some View {
        if libraryDataManager.isLoadingStarred {
            WRhythmLoadingState(
                systemImage: "star",
                title: "Loading favourites",
                message: nil
            )
        } else if !libraryDataManager.starredErrorMessage.isEmpty {
            WRhythmErrorState(
                title: "Favourites Error",
                message: libraryDataManager.starredErrorMessage
            ) {
                    libraryDataManager.fetchStarred(forceRefresh: true)
            }
        } else if let starred = libraryDataManager.starred {
            if (starred.song?.isEmpty ?? true) && (starred.album?.isEmpty ?? true) && (starred.artist?.isEmpty ?? true) {
                WRhythmEmptyState(
                    systemImage: "star",
                    title: "No favourites yet",
                    message: "Star items in Navidrome to see them here"
                )
            } else {
                let songsToShow = songSortOption.sorted(filteredSongs(starred.song ?? []))
                let albumsToShow = albumSortOption.sorted(filteredAlbums(starred.album ?? []))
                let artistsToShow = artistSortOption.sorted(filteredArtists(starred.artist ?? []))
                if songsToShow.isEmpty && albumsToShow.isEmpty && artistsToShow.isEmpty {
                    WRhythmEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No favourites found",
                        message: "Try a different search term"
                    )
                } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Starred Songs
                        if !songsToShow.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Songs")
                                        .font(WRhythmTypography.featureTitle)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        WRhythmSortMenu(selection: $songSortOption)
                                        if songsToShow.count > 1 {
                                            Button(action: {
                                                player.playQueue(songsToShow, startingAt: 0)
                                            }) {
                                                Image(systemName: "play.fill")
                                                    .font(WRhythmTypography.rowSubtitle)
                                            }
                                            Button(action: {
                                                player.playQueueShuffled(songsToShow)
                                            }) {
                                                Image(systemName: "shuffle")
                                                    .font(WRhythmTypography.rowSubtitle)
                                            }
                                        }
                                        if !offlineMode {
                                            Button(action: {
                                                // Download all favorited songs
                                                for song in songsToShow {
                                                    downloadManager.downloadSong(song)
                                                }
                                            }) {
                                                Image(systemName: "arrow.down.circle")
                                                    .font(WRhythmTypography.rowSubtitle)
                                            }
                                        }
                                    }
                                }

                                SlidingRenderWindowForEach(songsToShow, estimatedRowHeight: 64, resetToken: songSortOption) { index, song in
                                    TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: offlineMode) {
                                        player.playQueue(songsToShow, startingAt: index)
                                    }
                                }
                            }

                            Divider()
                        }

                        // Starred Albums
                        if !albumsToShow.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                WRhythmSectionHeader(title: "Albums") {
                                    WRhythmSortMenu(selection: $albumSortOption)
                                }

                                SlidingRenderWindowForEach(albumsToShow, estimatedRowHeight: 64, resetToken: albumSortOption) { _, album in
                                    NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                        WRhythmCollectionRow(
                                            title: album.name,
                                            subtitle: album.artist,
                                            detail: album.year.map(String.init),
                                            coverArtId: album.coverArt,
                                            fallbackSystemImage: "square.stack",
                                            tint: WRhythmTheme.album
                                        )
                                    }
                                    .wrhythmAlbumActions(albumId: album.id, albumName: album.name)
                                }
                            }

                            Divider()
                        }

                        // Starred Artists
                        if !artistsToShow.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                WRhythmSectionHeader(title: "Artists") {
                                    WRhythmSortMenu(selection: $artistSortOption)
                                }

                                SlidingRenderWindowForEach(artistsToShow, estimatedRowHeight: 64, resetToken: artistSortOption) { _, artist in
                                    NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                                        WRhythmCollectionRow(
                                            title: artist.name,
                                            subtitle: artist.albumCount.map { "\($0) albums" },
                                            coverArtId: artist.coverArt,
                                            fallbackSystemImage: "person.fill",
                                            tint: WRhythmTheme.artist
                                        )
                                    }
                                    .wrhythmArtistActions(artistId: artist.id, artistName: artist.name)
                                }
                            }
                        }
                    }
                    .padding()
#if os(iOS)
                    .padding(.top, WRhythmSpacing.md)
                    .padding(.bottom, WRhythmVisual.bottomNavigationClearance)
#endif
                }
#if os(iOS)
                .scrollIndicators(.hidden)
#endif
                }
            }
        } else {
            // Fallback state - shouldn't normally reach here
            WRhythmLoadingState(
                systemImage: "star",
                title: "Loading favourites",
                message: nil
            )
        }
    }

#if os(iOS)
    private var inlineSearchField: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(WRhythmTypography.bodyEmphasis)
                .foregroundStyle(WRhythmTheme.accent)

            TextField("Search favourites", text: $searchText)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear favourites search")
            }
        }
        .padding(.horizontal, WRhythmSpacing.md)
        .frame(minHeight: 46)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.accent.opacity(0.24), lineWidth: 1)
        }
    }
#endif
}

#Preview {
    NavigationStack {
        FavouritesView()
    }
}
