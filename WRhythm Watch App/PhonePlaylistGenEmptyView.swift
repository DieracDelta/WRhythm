//
//  PhonePlaylistGenEmptyView.swift
//  WRhythm
//

import SwiftUI

#if os(iOS)
struct PhonePlaylistGenEmptyView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: WRhythmSpacing.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 76, height: 76)
                .background(.thinMaterial, in: Circle())

            Text("No Playlist Gen")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, WRhythmSpacing.lg)
        .padding(.vertical, WRhythmSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
    }
}
#endif
