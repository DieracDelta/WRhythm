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
                VStack(alignment: .leading, spacing: WRhythmSpacing.xl) {
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

                    promptCard
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .frame(minHeight: usableHeight(for: proxy.size), alignment: .top)
                .padding(.horizontal, WRhythmSpacing.md)
                .padding(.top, 0)
                .padding(.bottom, WRhythmVisual.bottomNavigationClearance)
            }
            .scrollIndicators(.hidden)
            .safeAreaPadding(.top, -WRhythmSpacing.sm)
            .ignoresSafeArea(.container, edges: .top)
            .wrhythmPageBackground()
        }
    }

    private var promptCard: some View {
        VStack(spacing: WRhythmSpacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary)
                .frame(width: 86, height: 86)
                .background(.thinMaterial, in: Circle())

            VStack(spacing: WRhythmSpacing.xs) {
                Text(promptTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.horizontal, WRhythmSpacing.lg)
        .padding(.vertical, WRhythmSpacing.xl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
    }

    private func usableHeight(for size: CGSize) -> CGFloat {
        max(0, size.height - WRhythmVisual.bottomNavigationClearance)
    }
}
#endif
