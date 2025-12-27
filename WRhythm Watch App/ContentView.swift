//
//  ContentView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var api = NavidromeAPI.shared
    @ObservedObject var player = AudioPlayer.shared
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if api.isAuthenticated {
                TabView(selection: $selectedTab) {
                    NavigationView {
                        SpontaneousMusicView()
                    }
                    .tabItem {
                        Label("Spontaneous", systemImage: "shuffle")
                    }
                    .tag(0)

                    NavigationView {
                        ArtistsView()
                    }
                    .tabItem {
                        Label("Artists", systemImage: "person.2")
                    }
                    .tag(1)

                    NavigationView {
                        AlbumsView()
                    }
                    .tabItem {
                        Label("Albums", systemImage: "square.stack")
                    }
                    .tag(2)

                    NavigationView {
                        FavouritesView()
                    }
                    .tabItem {
                        Label("Favourites", systemImage: "star.fill")
                    }
                    .tag(3)

                    NavigationView {
                        PlaylistsView()
                    }
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                    .tag(4)

                    NavigationView {
                        RadioPlaylistsView()
                    }
                    .tabItem {
                        Label("Radio", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .tag(5)

                    NavigationView {
                        TracksView()
                    }
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(6)

                    NavigationView {
                        NowPlayingView()
                    }
                    .tabItem {
                        Label("Now Playing", systemImage: "play.circle.fill")
                    }
                    .tag(7)

                    NavigationView {
                        DownloadsView()
                    }
                    .tabItem {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                    .tag(8)

                    NavigationView {
                        SettingsView()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(9)
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // When app becomes active, go to Now Playing if music is playing
                        if player.isPlaying {
                            selectedTab = 7
                        }
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
