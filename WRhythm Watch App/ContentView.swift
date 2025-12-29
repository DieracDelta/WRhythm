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
                    MenuView()
                        .tabItem {
                            Label("Menu", systemImage: "list.bullet")
                        }
                        .tag(0)

                    NavigationView {
                        NowPlayingView()
                    }
                    .tabItem {
                        Label("Playing", systemImage: "play.circle.fill")
                    }
                    .tag(1)
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // When app becomes active, go to Now Playing if music is playing
                        if player.isPlaying {
                            selectedTab = 1
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
