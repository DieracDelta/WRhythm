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
                .padding(WRhythmSpacing.xl)
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

enum WRhythmTheme {
    static let accent = Color(red: 1.0, green: 0.67, blue: 0.24)
    static let secondaryAccent = Color(red: 0.23, green: 0.78, blue: 0.74)
    static let favorite = Color(red: 1.0, green: 0.30, blue: 0.38)
    static let playlistGen = Color(red: 0.62, green: 0.46, blue: 0.94)
    static let spontaneous = Color(red: 1.0, green: 0.57, blue: 0.21)
    static let downloads = Color(red: 0.34, green: 0.78, blue: 0.48)
    static let artist = Color(red: 0.38, green: 0.56, blue: 0.96)
    static let album = Color(red: 0.18, green: 0.72, blue: 0.68)
    static let warning = Color.orange
    static let success = Color.green
    static let danger = Color.red

    static func pageGradient(for colorScheme: ColorScheme) -> LinearGradient {
        let darkColors = [
            Color(red: 0.04, green: 0.04, blue: 0.04),
            Color(red: 0.10, green: 0.085, blue: 0.065),
            Color(red: 0.045, green: 0.055, blue: 0.06)
        ]
        let lightColors = [
            Color(red: 0.98, green: 0.97, blue: 0.94),
            Color(red: 0.94, green: 0.96, blue: 0.96),
            Color(red: 0.99, green: 0.98, blue: 0.96)
        ]

        return LinearGradient(
            colors: colorScheme == .dark ? darkColors : lightColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surfaceStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    static func controlFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }
}

enum WRhythmSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum WRhythmTypography {
    static let sectionLabel = Font.caption.weight(.semibold)
    static let rowTitle = Font.subheadline.weight(.semibold)
    static let rowSubtitle = Font.caption
    static let metadata = Font.caption2
    static let controlLabel = Font.caption.weight(.medium)
}

enum WRhythmVisual {
    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 10
    static let thumbnailCornerRadius: CGFloat = 8
    static let sectionSpacing: CGFloat = WRhythmSpacing.md
#if os(watchOS)
    static let cardPadding: CGFloat = WRhythmSpacing.sm
#else
    static let cardPadding: CGFloat = WRhythmSpacing.md
#endif
    static let bottomNavigationClearance: CGFloat = WRhythmSpacing.xl + WRhythmSpacing.xxl + WRhythmSpacing.xxl
    static let contentMaxWidth: CGFloat = 760
}

enum WRhythmSurfaceStyle {
    case grouped
    case glass
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
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = WRhythmVisual.cardPadding
    var style: WRhythmSurfaceStyle = .grouped
    private let content: Content

    init(
        padding: CGFloat = WRhythmVisual.cardPadding,
        style: WRhythmSurfaceStyle = .grouped,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surfaceFill, in: RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WRhythmVisual.compactCornerRadius, style: .continuous)
                    .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            }
    }

    private var surfaceFill: AnyShapeStyle {
        switch style {
        case .grouped:
            AnyShapeStyle(WRhythmTheme.controlFill(for: colorScheme))
        case .glass:
            AnyShapeStyle(.regularMaterial)
        }
    }
}

struct WRhythmGlassCard<Content: View>: View {
    var padding: CGFloat = WRhythmVisual.cardPadding
    private let content: Content

    init(padding: CGFloat = WRhythmVisual.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        WRhythmCard(padding: padding, style: .glass) {
            content
        }
    }
}

struct WRhythmHeroHeader<Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let detail: String?
    let systemImage: String
    var tint: Color = WRhythmTheme.accent
    var coverArtId: String?
    private let actions: Actions

    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String,
        tint: Color = WRhythmTheme.accent,
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
        VStack(spacing: WRhythmSpacing.md) {
            heroArt

            VStack(spacing: WRhythmSpacing.xs) {
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
                    colors: [tint.opacity(0.34), WRhythmTheme.secondaryAccent.opacity(0.16)],
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
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.12), radius: 24, y: 14)
    }
}

struct WRhythmActionStrip<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: WRhythmSpacing.xs) {
            content
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, WRhythmSpacing.sm)
        .padding(.vertical, WRhythmSpacing.xs)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
    }
}

extension WRhythmHeroHeader where Actions == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        systemImage: String,
        tint: Color = WRhythmTheme.accent,
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
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let systemImage: String
    var tint: Color = WRhythmTheme.accent
    var coverArtId: String?

    var body: some View {
        VStack(spacing: WRhythmSpacing.xs) {
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
                        colors: [tint.opacity(0.32), WRhythmTheme.secondaryAccent.opacity(0.12)],
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
                    .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 20, y: 10)

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
        HStack(alignment: .firstTextBaseline, spacing: WRhythmSpacing.sm) {
            VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
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
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    var tint: Color = WRhythmTheme.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(14, size * 0.42), weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(colorScheme == .dark ? 0.16 : 0.11), in: RoundedRectangle(cornerRadius: min(10, size * 0.28), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: min(10, size * 0.28), style: .continuous)
                    .strokeBorder(tint.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: 1)
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
        HStack(spacing: WRhythmSpacing.sm) {
            WRhythmArtworkThumbnail(coverArtId: coverArtId, fallbackSystemImage: fallbackSystemImage, size: artworkSize)

            VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                HStack(spacing: WRhythmSpacing.xs) {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker")
                            .font(.caption2)
                            .foregroundColor(WRhythmTheme.accent)
                    }
                    Text(title)
                        .font(WRhythmTypography.rowTitle)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(WRhythmTypography.metadata)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            trailing
        }
        .padding(.vertical, WRhythmSpacing.xs)
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
    var tint: Color = WRhythmTheme.accent
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        coverArtId: String? = nil,
        fallbackSystemImage: String,
        tint: Color = WRhythmTheme.accent,
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
        tint: Color = WRhythmTheme.accent
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
        HStack(spacing: WRhythmSpacing.xs) {
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

struct WRhythmRowIconButton: View {
    let systemImage: String
    var tint: Color = WRhythmTheme.accent
    var accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    @ViewBuilder
    func wrhythmPageBackground(coverArtId: String? = nil) -> some View {
        self.background(WRhythmArtworkBackdrop(coverArtId: coverArtId).ignoresSafeArea())
    }

    @ViewBuilder
    func wrhythmListSurface(coverArtId: String? = nil) -> some View {
#if os(iOS)
        self
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: WRhythmVisual.bottomNavigationClearance)
            }
            .background {
                if let coverArtId {
                    WRhythmArtworkBackdrop(coverArtId: coverArtId).ignoresSafeArea()
                } else {
                    WRhythmLibraryBackdrop().ignoresSafeArea()
                }
            }
#else
        self
            .scrollContentBackground(.hidden)
            .background {
                if let coverArtId {
                    WRhythmArtworkBackdrop(coverArtId: coverArtId).ignoresSafeArea()
                } else {
                    WRhythmLibraryBackdrop().ignoresSafeArea()
                }
            }
#endif
    }
}

struct WRhythmLibraryBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            WRhythmTheme.pageGradient(for: colorScheme)
            LinearGradient(
                colors: [
                    Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.02),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct WRhythmArtworkBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    let coverArtId: String?

    var body: some View {
        ZStack {
            WRhythmTheme.pageGradient(for: colorScheme)

            if let coverArtId,
               let coverURL = NavidromeAPI.shared.getCoverArtURL(id: coverArtId, size: 120) {
                CachedAsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .blur(radius: 32)
                .saturation(1.08)
                .opacity(colorScheme == .dark ? 0.22 : 0.14)
                .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    WRhythmTheme.accent.opacity(colorScheme == .dark ? 0.10 : 0.07),
                    WRhythmTheme.secondaryAccent.opacity(colorScheme == .dark ? 0.06 : 0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct WRhythmStatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: WRhythmSpacing.xs) {
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
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.22 : 0.18), lineWidth: 1)
        }
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
                .background(prominent ? AnyShapeStyle(WRhythmTheme.accent.gradient) : AnyShapeStyle(.regularMaterial), in: Circle())
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .shadow(color: Color.black.opacity(prominent ? 0.22 : 0.08), radius: prominent ? 16 : 8, y: prominent ? 8 : 4)
        }
        .buttonStyle(.plain)
    }
}

struct WRhythmArtworkThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
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
                LinearGradient(
                    colors: [
                        WRhythmTheme.accent.opacity(colorScheme == .dark ? 0.22 : 0.16),
                        WRhythmTheme.secondaryAccent.opacity(colorScheme == .dark ? 0.16 : 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: fallbackSystemImage)
                    .font(.system(size: max(16, size * 0.38), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
    }
}

struct WRhythmEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    let title: String
    let message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: WRhythmSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary)
                .frame(width: 72, height: 72)
                .background(.regularMaterial, in: Circle())

            VStack(spacing: WRhythmSpacing.xs) {
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
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
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
        HStack(spacing: WRhythmSpacing.xs) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
