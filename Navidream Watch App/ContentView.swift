//
//  ContentView.swift
//  Navidream Watch App
//
//  Created by Justin Restivo on 12/23/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var api = NavidromeAPI.shared
    @ObservedObject var player = AudioPlayer.shared

    var body: some View {
        Group {
            if api.isAuthenticated {
                TabView {
                    NavigationView {
                        ArtistsView()
                    }
                    .tabItem {
                        Label("Artists", systemImage: "music.note.list")
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
