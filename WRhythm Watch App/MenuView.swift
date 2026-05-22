//
//  MenuView.swift
//  WRhythm Watch App
//
//  Created by Justin Restivo on 12/29/25.
//

import SwiftUI

struct MenuView: View {
    private let menuIconTint = WRhythmTheme.playlistGen

    var body: some View {
        WRhythmScreen {
            menuGroup("Library") {
                menuLink("Artists", systemImage: "person.2", destination: ArtistsView())
                menuLink("Albums", systemImage: "square.stack", destination: AlbumsView())
                menuLink("Playlists", systemImage: "music.note.list", destination: PlaylistsView())
                menuLink("Tracks", systemImage: "magnifyingglass", destination: TracksView())
            }

            menuGroup("Playback") {
                menuLink("Favorites", systemImage: "star.fill", destination: FavouritesView())
                menuLink("Playlist Gen", systemImage: "radio", destination: RadioPlaylistsView())
                menuLink("Spontaneous", systemImage: "shuffle", destination: SpontaneousMusicView())
            }

            menuGroup("Device") {
                menuLink("Downloads", systemImage: "arrow.down.circle", destination: DownloadsView())
                menuLink("Settings", systemImage: "gear", destination: SettingsView())
            }
        }
        .navigationTitle("")
        .platformNavigationBarTitleDisplayModeInline()
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
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

    private func menuLink<Destination: View>(_ title: String, systemImage: String, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: WRhythmSpacing.sm) {
                WRhythmIconBadge(systemImage: systemImage, tint: menuIconTint)

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
