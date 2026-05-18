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
                Section {
                    menuLink("Artists", systemImage: "person.2", tint: .indigo, destination: ArtistsView())
                    menuLink("Albums", systemImage: "square.stack", tint: .teal, destination: AlbumsView())
                    menuLink("Playlists", systemImage: "music.note.list", tint: .purple, destination: PlaylistsView())
                    menuLink("Tracks", systemImage: "magnifyingglass", tint: .blue, destination: TracksView())
                }

                Section {
                    menuLink("Favorites", systemImage: "star.fill", tint: .yellow, destination: FavouritesView())
                    menuLink("Playlist Gen", systemImage: "radio", tint: .pink, destination: RadioPlaylistsView())
                    menuLink("Spontaneous", systemImage: "shuffle", tint: .orange, destination: SpontaneousMusicView())
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
                Image(systemName: systemImage)
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(tint)
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(title)
                    .font(.headline)
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    MenuView()
}
