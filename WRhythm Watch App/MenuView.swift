//
//  MenuView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/29/25.
//

import SwiftUI

struct MenuView: View {
    var body: some View {
        WRhythmScreen {
            menuGroup("Library") {
                menuLink("Artists", systemImage: "person.2", tint: WRhythmTheme.secondaryAccent, destination: ArtistsView())
                menuLink("Albums", systemImage: "square.stack", tint: WRhythmTheme.accent, destination: AlbumsView())
                menuLink("Playlists", systemImage: "music.note.list", tint: WRhythmTheme.secondaryAccent, destination: PlaylistsView())
                menuLink("Tracks", systemImage: "magnifyingglass", tint: WRhythmTheme.accent, destination: TracksView())
            }

            menuGroup("Playback") {
                menuLink("Favorites", systemImage: "star.fill", tint: WRhythmTheme.favorite, destination: FavouritesView())
                menuLink("Playlist Gen", systemImage: "radio", tint: WRhythmTheme.playlistGen, destination: RadioPlaylistsView())
                menuLink("Spontaneous", systemImage: "shuffle", tint: WRhythmTheme.spontaneous, destination: SpontaneousMusicView())
            }

            menuGroup("Device") {
                menuLink("Downloads", systemImage: "arrow.down.circle", tint: WRhythmTheme.downloads, destination: DownloadsView())
                menuLink("Settings", systemImage: "gear", tint: .secondary, destination: SettingsView())
            }
        }
        .navigationTitle("")
        .platformNavigationBarTitleDisplayModeInline()
    }

    private func menuGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
            Text(title)
                .font(WRhythmTypography.sectionLabel)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, WRhythmSpacing.xxs)

            WRhythmCard {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }

    private func menuLink<Destination: View>(_ title: String, systemImage: String, tint: Color, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: WRhythmSpacing.sm) {
                WRhythmIconBadge(systemImage: systemImage, tint: tint)

                Text(title)
                    .font(WRhythmTypography.rowTitle)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(WRhythmTypography.metadata)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, WRhythmSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MenuView()
}
