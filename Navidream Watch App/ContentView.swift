//
//  ContentView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var api = NavidromeAPI.shared

    var body: some View {
        Group {
            if api.isAuthenticated {
                TabView {
                    NavigationView {
                        AlbumsView()
                    }
                    .tabItem {
                        Label("Albums", systemImage: "square.stack")
                    }

                    NavigationView {
                        PlaylistsView()
                    }
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }

                    NavigationView {
                        FavouritesView()
                    }
                    .tabItem {
                        Label("Favourites", systemImage: "star.fill")
                    }

                    NavigationView {
                        ArtistsView()
                    }
                    .tabItem {
                        Label("Artists", systemImage: "person.2")
                    }

                    NavigationView {
                        TracksView()
                    }
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    NavigationView {
                        SpontaneousMusicView()
                    }
                    .tabItem {
                        Label("Spontaneous", systemImage: "shuffle")
                    }

                    NavigationView {
                        DownloadsView()
                    }
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }

                    NavigationView {
                        RadioPlaylistsView()
                    }
                    .tabItem {
                        Label("Radio", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    NavigationView {
                        NowPlayingView()
                    }
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }

                    NavigationView {
                        SettingsView()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                }
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
}
