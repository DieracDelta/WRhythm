//
//  FavouritesView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct FavouritesView: View {
    @State private var starred: StarredContent?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @ObservedObject var downloadManager = DownloadManager.shared
    @AppStorage("offlineMode") private var offlineMode = false

    private var player: AudioPlayer { AudioPlayer.shared }

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
        Group {
            if offlineMode {
                // Offline mode: show starred songs from local cache
                if offlineStarredSongs.isEmpty {
                    VStack {
                        Image(systemName: "star")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No favourites available offline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Star and download songs while online to see them here")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
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
                                    TrackRowView(song: song) {
                                        player.playQueue(offlineStarredSongs, startingAt: index)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            } else if isLoading {
                ProgressView("Loading favourites...")
            } else if !errorMessage.isEmpty {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadStarred()
                    }
                }
            } else if let starred = starred {
                if (starred.song?.isEmpty ?? true) && (starred.album?.isEmpty ?? true) && (starred.artist?.isEmpty ?? true) {
                    VStack {
                        Image(systemName: "star")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No favourites yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Star items in Navidrome to see them here")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
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
                                        TrackRowView(song: song) {
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
                                            HStack {
                                                if let coverArtId = album.coverArt,
                                                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                                    CachedAsyncImage(url: coverURL) { image in
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                    }
                                                    .frame(width: 40, height: 40)
                                                    .cornerRadius(4)
                                                    .id(coverURL)
                                                }

                                                VStack(alignment: .leading) {
                                                    Text(album.name)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                    if let artist = album.artist {
                                                        Text(artist)
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                            }
                                        }
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
                                            HStack {
                                                if let coverArtId = artist.coverArt,
                                                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                                    CachedAsyncImage(url: coverURL) { image in
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                    }
                                                    .frame(width: 40, height: 40)
                                                    .cornerRadius(4)
                                                    .id(coverURL)
                                                }

                                                VStack(alignment: .leading) {
                                                    Text(artist.name)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                    if let albumCount = artist.albumCount {
                                                        Text("\(albumCount) albums")
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                        }
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
                VStack {
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    print("⚠️ FavouritesView in unexpected state - starred=nil, isLoading=\(isLoading), offlineMode=\(offlineMode)")
                }
            }
        }
        .navigationTitle("Favourites")
        .onAppear {
            print("📱 FavouritesView appeared - offlineMode=\(offlineMode), starred=\(starred != nil ? "loaded" : "nil"), isLoading=\(isLoading)")
            if !offlineMode && starred == nil && !isLoading {
                loadStarred()
            }
        }
    }

    private func loadStarred() {
        print("🔄 FavouritesView: Starting to load starred content...")
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedStarred = try await NavidromeAPI.shared.getStarred()
                print("✅ FavouritesView: Received starred content - songs: \(fetchedStarred.song?.count ?? 0), albums: \(fetchedStarred.album?.count ?? 0), artists: \(fetchedStarred.artist?.count ?? 0)")
                await MainActor.run {
                    self.starred = fetchedStarred
                    self.isLoading = false
                    print("✅ FavouritesView: Updated state - starred is now set")
                }
            } catch {
                print("❌ FavouritesView: Failed to load starred content: \(error)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        FavouritesView()
    }
}
