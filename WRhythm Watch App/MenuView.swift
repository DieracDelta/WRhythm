//
//  MenuView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/29/25.
//

import SwiftUI

struct MenuView: View {
    var body: some View {
        List {
            WRhythmFeatureHeader(
                title: "WRhythm",
                subtitle: nil,
                systemImage: "waveform",
                tint: WRhythmTheme.accent
            )
            .listRowBackground(Color.clear)

            Section("Library") {
                menuLink("Artists", systemImage: "person.2", tint: WRhythmTheme.secondaryAccent, destination: ArtistsView())
                menuLink("Albums", systemImage: "square.stack", tint: WRhythmTheme.accent, destination: AlbumsView())
                menuLink("Playlists", systemImage: "music.note.list", tint: WRhythmTheme.secondaryAccent, destination: PlaylistsView())
                menuLink("Tracks", systemImage: "magnifyingglass", tint: WRhythmTheme.accent, destination: TracksView())
            }

            Section("Playback") {
                menuLink("Favorites", systemImage: "star.fill", tint: WRhythmTheme.favorite, destination: FavouritesView())
                menuLink("Playlist Gen", systemImage: "radio", tint: WRhythmTheme.accent, destination: RadioPlaylistsView())
                menuLink("Spontaneous", systemImage: "shuffle", tint: .orange, destination: SpontaneousMusicView())
            }

            Section("Device") {
                menuLink("Downloads", systemImage: "arrow.down.circle", tint: WRhythmTheme.success, destination: DownloadsView())
                menuLink("Settings", systemImage: "gear", tint: .secondary, destination: SettingsView())
            }
        }
        .navigationTitle("WRhythm")
        .wrhythmListSurface()
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
