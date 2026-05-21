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
                Section("Library") {
                    menuLink("Artists", systemImage: "person.2", tint: .indigo, destination: ArtistsView())
                    menuLink("Albums", systemImage: "square.stack", tint: .teal, destination: AlbumsView())
                    menuLink("Playlists", systemImage: "music.note.list", tint: .purple, destination: PlaylistsView())
                    menuLink("Tracks", systemImage: "magnifyingglass", tint: .blue, destination: TracksView())
                }

                Section("Playback") {
                    menuLink("Favorites", systemImage: "star.fill", tint: .yellow, destination: FavouritesView())
                    menuLink("Playlist Gen", systemImage: "radio", tint: .pink, destination: RadioPlaylistsView())
                    menuLink("Spontaneous", systemImage: "shuffle", tint: .orange, destination: SpontaneousMusicView())
                }

                Section("Device") {
                    menuLink("Downloads", systemImage: "arrow.down.circle", tint: .green, destination: DownloadsView())
                    menuLink("Settings", systemImage: "gear", tint: .secondary, destination: SettingsView())
                }
            }
            .navigationTitle("WRhythm")
            .wrhythmListSurface()
        }
    }

    private func menuLink<Destination: View>(_ title: String, systemImage: String, tint: Color, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                WRhythmIconBadge(systemImage: systemImage, tint: tint)

                Text(title)
                    .font(.headline)

                Spacer(minLength: 6)
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    MenuView()
}
