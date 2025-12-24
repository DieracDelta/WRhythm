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
            if isLoading {
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
                                        if songsToShow.count > 1 {
                                            HStack(spacing: 8) {
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
                                        }
                                    }

                                    ForEach(Array(songsToShow.enumerated()), id: \.element.id) { index, song in
                                        Button(action: {
                                            player.playQueue(songsToShow, startingAt: index)
                                        }) {
                                            HStack {
                                                if let coverArtId = song.coverArt,
                                                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 100) {
                                                    AsyncImage(url: coverURL) { image in
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Color.gray
                                                    }
                                                    .frame(width: 40, height: 40)
                                                    .cornerRadius(4)
                                                    .id(coverURL)
                                                }

                                                VStack(alignment: .leading) {
                                                    Text(song.title)
                                                        .font(.caption)
                                                        .lineLimit(1)
                                                    if let artist = song.artist {
                                                        Text(artist)
                                                            .font(.caption2)
                                                            .foregroundColor(.secondary)
                                                            .lineLimit(1)
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
                                            }
                                        }
                                        .buttonStyle(.plain)
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
                                                    AsyncImage(url: coverURL) { image in
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Color.gray
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
                                                    AsyncImage(url: coverURL) { image in
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Color.gray
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
            }
        }
        .navigationTitle("Favourites")
        .onAppear {
            if !offlineMode && starred == nil {
                loadStarred()
            }
        }
    }

    private func loadStarred() {
        isLoading = true
        errorMessage = ""

        Task {
            do {
                let fetchedStarred = try await NavidromeAPI.shared.getStarred()
                await MainActor.run {
                    self.starred = fetchedStarred
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
}

#Preview {
    NavigationView {
        FavouritesView()
    }
}
