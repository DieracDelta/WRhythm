//
//  FavouritesView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct FavouritesView: View {
    @EnvironmentObject var libraryDataManager: LibraryDataManager
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
        if offlineMode {
            return songs.filter { downloadManager.isDownloaded($0.id) }
        }
        return songs
    }

    private func filteredAlbums(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        if offlineMode {
            return albums.filter { downloadManager.hasDownloadedSongsForAlbum($0.id) }
        }
        return albums
    }

    private func filteredArtists(_ artists: [Artist]) -> [Artist] {
        if offlineMode {
            return artists.filter { artist in
                downloadManager.downloadedSongs.values.contains { song in
                    song.artist == artist.name
                }
            }
        }
        return artists
    }

    var body: some View {
        content
            .navigationTitle("Favourites")
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
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Songs")
                                .font(.headline)
                            Spacer()
                            if offlineStarredSongs.count > 1 {
                                HStack(spacing: 8) {
                                    Button(action: {
                                        player.playQueue(offlineStarredSongs, startingAt: 0)
                                    }) {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                    }
                                    Button(action: {
                                        player.playQueueShuffled(offlineStarredSongs)
                                    }) {
                                        Image(systemName: "shuffle")
                                            .font(.caption)
                                    }
                                }
                            }
                        }

                        ForEach(Array(offlineStarredSongs.enumerated()), id: \.element.id) { index, song in
                            TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: offlineMode) {
                                player.playQueue(offlineStarredSongs, startingAt: index)
                            }
                        }
                    }
                }
                .padding()
            }
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
                ScrollView {
                    VStack(spacing: 16) {
                        // Starred Songs
                        if let songs = starred.song, !songs.isEmpty {
                            let songsToShow = filteredSongs(songs)
                            if !songsToShow.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Songs")
                                        .font(.headline)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        if songsToShow.count > 1 {
                                            Button(action: {
                                                player.playQueue(songsToShow, startingAt: 0)
                                            }) {
                                                Image(systemName: "play.fill")
                                                    .font(.caption)
                                            }
                                            Button(action: {
                                                player.playQueueShuffled(songsToShow)
                                            }) {
                                                Image(systemName: "shuffle")
                                                    .font(.caption)
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
                                                    .font(.caption)
                                            }
                                        }
                                    }
                                }

                                ForEach(Array(songsToShow.enumerated()), id: \.element.id) { index, song in
                                    TrackRowView(song: song, player: player, downloadManager: downloadManager, offlineMode: offlineMode) {
                                        player.playQueue(songsToShow, startingAt: index)
                                    }
                                }
                            }

                            Divider()
                            }
                        }

                        // Starred Albums
                        if let albums = starred.album, !albums.isEmpty {
                            let albumsToShow = filteredAlbums(albums)
                            if !albumsToShow.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Albums")
                                    .font(.headline)

                                ForEach(albumsToShow) { album in
                                    NavigationLink(destination: AlbumDetailView(albumId: album.id)) {
                                        WRhythmCollectionRow(
                                            title: album.name,
                                            subtitle: album.artist,
                                            detail: album.year.map(String.init),
                                            coverArtId: album.coverArt,
                                            fallbackSystemImage: "square.stack",
                                            tint: .teal
                                        )
                                    }
                                    .wrhythmAlbumActions(albumId: album.id, albumName: album.name)
                                }
                            }

                            Divider()
                            }
                        }

                        // Starred Artists
                        if let artists = starred.artist, !artists.isEmpty {
                            let artistsToShow = filteredArtists(artists)
                            if !artistsToShow.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Artists")
                                    .font(.headline)

                                ForEach(artistsToShow) { artist in
                                    NavigationLink(destination: ArtistDetailView(artistId: artist.id, artistName: artist.name)) {
                                        WRhythmCollectionRow(
                                            title: artist.name,
                                            subtitle: artist.albumCount.map { "\($0) albums" },
                                            coverArtId: artist.coverArt,
                                            fallbackSystemImage: "person.fill",
                                            tint: .indigo
                                        )
                                    }
                                    .wrhythmArtistActions(artistId: artist.id, artistName: artist.name)
                                }
                            }
                            }
                        }
                    }
                    .padding()
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
}

#Preview {
    NavigationView {
        FavouritesView()
    }
}
