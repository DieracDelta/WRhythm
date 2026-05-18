//
//  PlatformCompatibility.swift
//  WRhythm
//

import SwiftUI

extension ToolbarItemPlacement {
    static var platformTopBarTrailing: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .topBarTrailing
#endif
    }
}

extension View {
    @ViewBuilder
    func platformNavigationBarTitleDisplayModeInline() -> some View {
#if os(macOS)
        self
#else
        self.navigationBarTitleDisplayMode(.inline)
#endif
    }

    @ViewBuilder
    func platformAutocapitalizationNever() -> some View {
#if os(iOS) || os(watchOS)
        self.textInputAutocapitalization(.never)
#else
        self
#endif
    }

    @ViewBuilder
    func platformAutocapitalizationCharacters() -> some View {
#if os(iOS) || os(watchOS)
        self.textInputAutocapitalization(.characters)
#else
        self
#endif
    }

    @ViewBuilder
    func platformSearchSheetFrame() -> some View {
#if os(macOS)
        self
            .frame(minWidth: 420, idealWidth: 420, minHeight: 220, idealHeight: 220)
#else
        self
#endif
    }

    @ViewBuilder
    func platformSearchTextFieldStyle() -> some View {
#if os(watchOS)
        self
#else
        self.textFieldStyle(.roundedBorder)
#endif
    }
}

struct PlatformSearchSheet<Content: View>: View {
    let title: String
    let onCancel: () -> Void
    private let content: Content

    init(_ title: String, onCancel: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onCancel = onCancel
        self.content = content()
    }

    var body: some View {
#if os(macOS)
        VStack(spacing: 0) {
            content
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 220)
#else
        NavigationView {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                }
        }
#endif
    }
}

enum WRhythmVisual {
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 12

    static var pageBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.22),
                Color.black.opacity(0.16),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct WRhythmArtworkBackdrop: View {
    let coverArtId: String?

    var body: some View {
        ZStack {
            WRhythmVisual.pageBackground

            if let coverArtId,
               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 120) {
                CachedAsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .blur(radius: 32)
                .saturation(1.15)
                .opacity(0.28)
                .ignoresSafeArea()
            }
        }
    }
}

struct WRhythmStatusPill: View {
    let text: String
    let systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundColor(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }
}

struct WRhythmTransportButton: View {
    let systemImage: String
    var size: Font = .title2
    var prominent = false
    var diameter: CGFloat?
    let action: () -> Void

    var body: some View {
        let resolvedDiameter = diameter ?? (prominent ? 64 : 44)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(size)
                .symbolRenderingMode(.hierarchical)
                .frame(width: resolvedDiameter, height: resolvedDiameter)
                .background(prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.regularMaterial), in: Circle())
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .shadow(color: Color.black.opacity(prominent ? 0.22 : 0.08), radius: prominent ? 16 : 8, y: prominent ? 8 : 4)
        }
        .buttonStyle(.plain)
    }
}
