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
    static let thumbnailCornerRadius: CGFloat = 9
    static let sectionSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let contentMaxWidth: CGFloat = 760

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

struct WRhythmScreen<Content: View>: View {
    var coverArtId: String?
    var horizontalPadding: CGFloat = 16
    private let content: Content

    init(
        coverArtId: String? = nil,
        horizontalPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.coverArtId = coverArtId
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WRhythmVisual.sectionSpacing) {
                content
            }
            .frame(maxWidth: WRhythmVisual.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 16)
        }
        .wrhythmPageBackground(coverArtId: coverArtId)
    }
}

struct WRhythmCard<Content: View>: View {
    var padding: CGFloat = WRhythmVisual.cardPadding
    private let content: Content

    init(padding: CGFloat = WRhythmVisual.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}

struct WRhythmHeroHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let detail: String?
    let systemImage: String
    var tint: Color = .accentColor
    var coverArtId: String?
    private let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String,
        tint: Color = .accentColor,
        coverArtId: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
        self.coverArtId = coverArtId
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 14) {
            heroArt

            VStack(spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var heroArt: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .fill(.regularMaterial)

            if let coverArtId,
               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 420) {
                CachedAsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                LinearGradient(
                    colors: [tint.opacity(0.46), Color.primary.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: systemImage)
                    .font(.system(size: 58, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(tint)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.20), radius: 22, y: 12)
    }
}

struct WRhythmActionStrip<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
    }
}

extension WRhythmHeroHeader where Actions == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String,
        tint: Color = .accentColor,
        coverArtId: String? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            detail: detail,
            systemImage: systemImage,
            tint: tint,
            coverArtId: coverArtId
        ) {
            EmptyView()
        }
    }
}

struct WRhythmFeatureHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var tint: Color = .accentColor
    var coverArtId: String?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let coverArtId,
                   let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 180) {
                    CachedAsyncImage(url: coverURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .saturation(1.08)
                } else {
                    LinearGradient(
                        colors: [tint.opacity(0.42), Color.primary.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: systemImage)
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(tint)
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.20), radius: 20, y: 10)

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

struct WRhythmSectionHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    private let actions: Actions

    init(title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            actions
        }
        .padding(.horizontal, 2)
    }
}

extension WRhythmSectionHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct WRhythmIconBadge: View {
    let systemImage: String
    var tint: Color = .accentColor
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(14, size * 0.42), weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: min(10, size * 0.28), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: min(10, size * 0.28), style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

struct WRhythmMediaRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var detail: String?
    var coverArtId: String?
    var fallbackSystemImage = "music.note"
    var artworkSize: CGFloat = 46
    var isCurrent = false
    var isPlaying = false
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        coverArtId: String? = nil,
        fallbackSystemImage: String = "music.note",
        artworkSize: CGFloat = 46,
        isCurrent: Bool = false,
        isPlaying: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.coverArtId = coverArtId
        self.fallbackSystemImage = fallbackSystemImage
        self.artworkSize = artworkSize
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 11) {
            WRhythmArtworkThumbnail(coverArtId: coverArtId, fallbackSystemImage: fallbackSystemImage, size: artworkSize)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            trailing
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

extension WRhythmMediaRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        coverArtId: String? = nil,
        fallbackSystemImage: String = "music.note",
        artworkSize: CGFloat = 46,
        isCurrent: Bool = false,
        isPlaying: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            detail: detail,
            coverArtId: coverArtId,
            fallbackSystemImage: fallbackSystemImage,
            artworkSize: artworkSize,
            isCurrent: isCurrent,
            isPlaying: isPlaying
        ) {
            EmptyView()
        }
    }
}

struct WRhythmCollectionRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var detail: String?
    var coverArtId: String?
    var fallbackSystemImage: String
    var tint: Color = .accentColor
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        coverArtId: String? = nil,
        fallbackSystemImage: String,
        tint: Color = .accentColor,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.coverArtId = coverArtId
        self.fallbackSystemImage = fallbackSystemImage
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        WRhythmMediaRow(
            title: title,
            subtitle: subtitle,
            detail: detail,
            coverArtId: coverArtId,
            fallbackSystemImage: fallbackSystemImage,
            artworkSize: 48
        ) {
            trailing
        }
    }
}

extension WRhythmCollectionRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        coverArtId: String? = nil,
        fallbackSystemImage: String,
        tint: Color = .accentColor
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            detail: detail,
            coverArtId: coverArtId,
            fallbackSystemImage: fallbackSystemImage,
            tint: tint
        ) {
            EmptyView()
        }
    }
}

struct WRhythmMetricRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
    }
}

extension View {
    @ViewBuilder
    func wrhythmPageBackground(coverArtId: String? = nil) -> some View {
        self.background(WRhythmArtworkBackdrop(coverArtId: coverArtId).ignoresSafeArea())
    }

    @ViewBuilder
    func wrhythmListSurface(coverArtId: String? = nil) -> some View {
        self
            .scrollContentBackground(.hidden)
            .wrhythmPageBackground(coverArtId: coverArtId)
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

struct WRhythmArtworkThumbnail: View {
    let coverArtId: String?
    var fallbackSystemImage = "music.note"
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous)
                .fill(.thinMaterial)

            if let coverArtId,
               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: Int(size * 3)) {
                CachedAsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: max(16, size * 0.38), weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

struct WRhythmEmptyState: View {
    let systemImage: String
    let title: String
    let message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary)
                .frame(width: 72, height: 72)
                .background(.regularMaterial, in: Circle())

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WRhythmLoadingState: View {
    let title: String
    var message: String?
    var systemImage = "arrow.triangle.2.circlepath"

    init(systemImage: String = "arrow.triangle.2.circlepath", title: String, message: String?) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        WRhythmEmptyState(systemImage: systemImage, title: title, message: message)
            .overlay {
                ProgressView()
                    .padding(.top, 96)
            }
    }
}

struct WRhythmErrorState: View {
    let title: String
    let message: String
    var actionTitle = "Retry"
    let action: () -> Void

    var body: some View {
        WRhythmEmptyState(
            systemImage: "exclamationmark.triangle.fill",
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action
        )
    }
}

struct WRhythmActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
