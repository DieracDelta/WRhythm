//
//  PhoneDownloadsEmptyView.swift
//  WRhythm
//

import SwiftUI

#if os(iOS)
struct PhoneDownloadsEmptyView: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WRhythmSpacing.xl) {
            Text("Downloads")
                .font(WRhythmTypography.appTitle)
                .lineLimit(1)

            VStack(spacing: WRhythmSpacing.md) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 38, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WRhythmTheme.downloads)
                    .frame(width: 76, height: 76)
                    .background(.thinMaterial, in: Circle())

                VStack(spacing: WRhythmSpacing.xs) {
                    Text("No Downloads")
                        .font(WRhythmTypography.featureTitle)
                        .multilineTextAlignment(.center)

                    if let message {
                        Text(message)
                            .font(WRhythmTypography.subhead)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
#endif
