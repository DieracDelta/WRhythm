//
//  PhoneSearchPromptView.swift
//  WRhythm
//

import SwiftUI

#if os(iOS)
struct PhoneSearchPromptView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let promptTitle: String
    let message: String?
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: WRhythmSpacing.lg) {
                    HStack(alignment: .center, spacing: WRhythmSpacing.md) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .lineLimit(1)

                        Spacer(minLength: WRhythmSpacing.sm)

                        Button(action: action) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(WRhythmTheme.accent)
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(actionTitle)
                    }

                    searchButton
                        .frame(maxWidth: searchButtonMaxWidth(for: proxy.size), alignment: .leading)

                    Spacer(minLength: 0)
                }
                .frame(minHeight: usableHeight(for: proxy.size), alignment: .top)
                .padding(.horizontal, WRhythmSpacing.md)
                .padding(.top, WRhythmSpacing.md)
                .padding(.bottom, WRhythmVisual.bottomNavigationClearance)
            }
            .scrollIndicators(.hidden)
            .wrhythmPageBackground()
        }
    }

    private var searchButton: some View {
        Button(action: action) {
            HStack(spacing: WRhythmSpacing.md) {
                searchGlyph

                VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                    Text(promptTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: WRhythmSpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, WRhythmSpacing.md)
            .frame(height: 64)
            .contentShape(RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(WRhythmTheme.controlFill(for: colorScheme), in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
        .accessibilityLabel(actionTitle)
        .accessibilityHint("Opens music search")
    }

    private var searchGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous)
                .fill(WRhythmTheme.accent.opacity(colorScheme == .dark ? 0.16 : 0.12))

            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WRhythmTheme.accent)
        }
        .frame(width: 42, height: 42)
    }

    private func usableHeight(for size: CGSize) -> CGFloat {
        max(0, size.height - WRhythmVisual.bottomNavigationClearance)
    }

    private func searchButtonMaxWidth(for size: CGSize) -> CGFloat {
        min(size.width - (WRhythmSpacing.md * 2), 480)
    }
}
#endif
