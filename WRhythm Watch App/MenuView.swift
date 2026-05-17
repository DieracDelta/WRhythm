//
//  MenuView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/29/25.
//

import SwiftUI

struct MenuView: View {
    var body: some View {
        NavigationView {
            List {
                NavigationLink(destination: ArtistsView()) {
                    Label("Artists", systemImage: "person.2")
                }

                NavigationLink(destination: PlaylistsView()) {
                    Label("Playlists", systemImage: "music.note.list")
                }

                NavigationLink(destination: FavouritesView()) {
                    Label("Favorites", systemImage: "star.fill")
                }

                NavigationLink(destination: RadioPlaylistsView()) {
                    Label("Playlist Gen", systemImage: "music.note.list")
                }

                NavigationLink(destination: TracksView()) {
                    Label("Tracks", systemImage: "magnifyingglass")
                }

                NavigationLink(destination: SpontaneousMusicView()) {
                    Label("Spontaneous", systemImage: "shuffle")
                }

                NavigationLink(destination: AlbumsView()) {
                    Label("Albums", systemImage: "square.stack")
                }

                NavigationLink(destination: DownloadsView()) {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }

                NavigationLink(destination: SettingsView()) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("WRhythm")
        }
    }
}

#Preview {
    MenuView()
}
