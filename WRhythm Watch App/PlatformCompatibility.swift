//
//  PlatformCompatibility.swift
//  WRhythm
//

import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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

    func platformExplicitCloseModal() -> some View {
#if os(macOS)
        self
#else
        self.interactiveDismissDisabled()
#endif
    }

    func platformModalCloseToolbar(action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                PlatformModalCloseButton(action: action)
            }
        }
    }
}

struct PlatformModalCloseButton: View {
    let action: () -> Void

    var body: some View {
        closeButton
#if !os(watchOS)
            .keyboardShortcut(.cancelAction)
#endif
            .accessibilityLabel("Close")
            .accessibilityHint("Closes this popup")
    }

    private var closeButton: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(WRhythmTypography.bodyEmphasis)
        }
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
            HStack {
                Spacer()
                PlatformModalCloseButton(action: onCancel)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, WRhythmSpacing.md)
            .padding(.top, WRhythmSpacing.sm)

            content
                .padding(WRhythmSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 420, height: 220)
#else
        NavigationStack {
            content
                .navigationTitle(title)
                .platformModalCloseToolbar(action: onCancel)
        }
        .platformExplicitCloseModal()
#endif
    }
}

enum WRhythmTheme {
    static let accent = Color(red: 1.0, green: 0.67, blue: 0.24)
    static let secondaryAccent = Color(red: 1.0, green: 0.78, blue: 0.34)
    static let favorite = accent
    static let playlistGen = accent
    static let spontaneous = accent
    static let downloads = accent
    static let artist = accent
    static let album = accent
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
    static let appTitle = WRhythmFont.bold(.largeTitle)
    static let screenTitle = WRhythmFont.bold(.title)
    static let heroTitle = WRhythmFont.semiBold(.title3)
    static let featureTitle = WRhythmFont.semiBold(.headline)
    static let sectionLabel = WRhythmFont.semiBold(.caption)
    static let body = WRhythmFont.regular(.body)
    static let bodyEmphasis = WRhythmFont.semiBold(.body)
    static let subhead = WRhythmFont.regular(.subheadline)
    static let subheadEmphasis = WRhythmFont.medium(.subheadline)
    static let rowTitle = WRhythmFont.semiBold(.subheadline)
    static let rowSubtitle = WRhythmFont.regular(.caption)
    static let metadata = WRhythmFont.regular(.caption2)
    static let metadataEmphasis = WRhythmFont.semiBold(.caption2)
    static let controlLabel = WRhythmFont.medium(.caption)
    static let controlLabelEmphasis = WRhythmFont.semiBold(.caption)
    static let numericValue = WRhythmFont.semiBold(.title3)
    static let timer = WRhythmFont.regular(.caption2)

    static func queueTitle(isCurrent: Bool) -> Font {
        isCurrent ? WRhythmFont.semiBold(.subheadline) : WRhythmFont.medium(.subheadline)
    }

    static func queueCompactTitle(isCurrent: Bool) -> Font {
        isCurrent ? WRhythmFont.semiBold(.caption) : WRhythmFont.regular(.caption)
    }
}

enum WRhythmFont {
    enum Face: String, CaseIterable {
        case regular = "ChakraPetch-Regular"
        case medium = "ChakraPetch-Medium"
        case semiBold = "ChakraPetch-SemiBold"
        case bold = "ChakraPetch-Bold"
    }

    private static let fileNames = [
        "ChakraPetch-Regular",
        "ChakraPetch-Medium",
        "ChakraPetch-SemiBold",
        "ChakraPetch-Bold",
    ]

    private static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        var registeredNames = Set(CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? [])
        for fileName in fileNames {
            guard !registeredNames.contains(fileName) else { continue }

            let url = Bundle.main.url(forResource: fileName, withExtension: "ttf", subdirectory: "Resources/Fonts")
                ?? Bundle.main.url(forResource: fileName, withExtension: "ttf")
            guard let url else { continue }

            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registeredNames.insert(fileName)
            }
        }
    }

    static func regular(_ textStyle: Font.TextStyle) -> Font {
        custom(.regular, textStyle)
    }

    static func medium(_ textStyle: Font.TextStyle) -> Font {
        custom(.medium, textStyle)
    }

    static func semiBold(_ textStyle: Font.TextStyle) -> Font {
        custom(.semiBold, textStyle)
    }

    static func bold(_ textStyle: Font.TextStyle) -> Font {
        custom(.bold, textStyle)
    }

    private static func custom(_ face: Face, _ textStyle: Font.TextStyle) -> Font {
        Font.custom(face.rawValue, size: pointSize(for: textStyle), relativeTo: textStyle)
    }

    private static func pointSize(for textStyle: Font.TextStyle) -> CGFloat {
        switch textStyle {
        case .largeTitle:
            34
        case .title:
            28
        case .title2:
            22
        case .title3:
            20
        case .headline, .body:
            17
        case .subheadline:
            15
        case .callout:
            16
        case .footnote:
            13
        case .caption:
            12
        case .caption2:
            11
        @unknown default:
            15
        }
    }
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
#if os(iOS)
    static let topNavigationClearance: CGFloat = WRhythmSpacing.xxl + WRhythmSpacing.xxl + WRhythmSpacing.sm
#else
    static let topNavigationClearance: CGFloat = WRhythmSpacing.xxl + WRhythmSpacing.xxl + WRhythmSpacing.xs
#endif
    static let contentMaxWidth: CGFloat = 760
}

enum WRhythmSurfaceStyle {
    case grouped
    case glass
}

struct WRhythmScreen<Content: View>: View {
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    var coverArtId: String?
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 16
    var contentMaxWidth: CGFloat = WRhythmVisual.contentMaxWidth
    private let content: Content

    init(
        coverArtId: String? = nil,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        contentMaxWidth: CGFloat = WRhythmVisual.contentMaxWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.coverArtId = coverArtId
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.contentMaxWidth = contentMaxWidth
        self.content = content()
    }

    var body: some View {
#if os(iOS)
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: WRhythmVisual.sectionSpacing) {
                    content
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .frame(minHeight: max(0, proxy.size.height - WRhythmVisual.bottomNavigationClearance), alignment: .top)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, WRhythmSpacing.md + topNavigationClearance)
                .padding(.bottom, WRhythmVisual.bottomNavigationClearance)
            }
            .scrollIndicators(.hidden)
        }
        .wrhythmPageBackground(coverArtId: coverArtId)
#else
        ScrollView {
            VStack(spacing: WRhythmVisual.sectionSpacing) {
                content
            }
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .wrhythmPageBackground(coverArtId: coverArtId)
#endif
    }

#if os(iOS)
    private var topNavigationClearance: CGFloat {
        horizontalSizeClass == .regular ? WRhythmVisual.topNavigationClearance : 0
    }
#endif
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
                    .font(WRhythmTypography.heroTitle)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WRhythmTypography.rowTitle)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(WRhythmTypography.rowSubtitle)
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
               let coverURL = StoredAlbumArtworkCache.displayURL(for: coverArtId, size: 420) {
                CachedAsyncImage(url: coverURL, storedCoverArtId: coverArtId) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                tint.opacity(colorScheme == .dark ? 0.18 : 0.12)
                Image(systemName: systemImage)
                    .font(.system(size: heroSymbolSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(tint)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: heroMaxSize)
        .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06), radius: 12, y: 6)
    }

    private var heroMaxSize: CGFloat {
#if os(watchOS)
        132
#else
        260
#endif
    }

    private var heroSymbolSize: CGFloat {
#if os(watchOS)
        36
#else
        50
#endif
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
    var logoImageName: String?

    var body: some View {
        VStack(spacing: WRhythmSpacing.xs) {
            ZStack {
                if let coverArtId,
                   let coverURL = StoredAlbumArtworkCache.displayURL(for: coverArtId, size: 180) {
                    CachedAsyncImage(url: coverURL, storedCoverArtId: coverArtId) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .saturation(1.08)
                } else {
                    tint.opacity(colorScheme == .dark ? 0.18 : 0.12)
                    if let logoImageName {
                        Image(logoImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(featureLogoPadding)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: featureSymbolSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(tint)
                    }
                }
            }
            .frame(width: featureArtSize, height: featureArtSize)
            .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WRhythmVisual.cornerRadius, style: .continuous)
                    .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05), radius: 10, y: 5)

            VStack(spacing: WRhythmSpacing.xxs) {
                Text(title)
                    .font(WRhythmTypography.featureTitle)
                    .multilineTextAlignment(.center)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WRhythmTypography.rowSubtitle)
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

    private var featureArtSize: CGFloat {
#if os(watchOS)
        64
#else
        80
#endif
    }

    private var featureSymbolSize: CGFloat {
#if os(watchOS)
        30
#else
        38
#endif
    }

    private var featureLogoPadding: CGFloat {
#if os(watchOS)
        10
#else
        12
#endif
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
                    .font(WRhythmTypography.featureTitle)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(WRhythmTypography.rowSubtitle)
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

#if os(iOS)
struct PhoneSearchSubmenuHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let countText: String
    var queryText: String?

    var body: some View {
        WRhythmCard {
            HStack(alignment: .center, spacing: WRhythmSpacing.md) {
                WRhythmIconBadge(systemImage: systemImage, tint: WRhythmTheme.accent, size: 52)

                VStack(alignment: .leading, spacing: WRhythmSpacing.xs) {
                    Text(title)
                        .font(WRhythmTypography.heroTitle)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: WRhythmSpacing.xs) {
                        WRhythmStatusPill(text: countText, systemImage: "sparkles", tint: WRhythmTheme.accent)

                        if let queryText, !queryText.isEmpty {
                            WRhythmStatusPill(text: queryText, systemImage: "magnifyingglass", tint: .secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .listRowInsets(EdgeInsets(top: WRhythmSpacing.sm, leading: WRhythmSpacing.md, bottom: WRhythmSpacing.sm, trailing: WRhythmSpacing.md))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
#endif

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
    var fallbackTint: Color = WRhythmTheme.accent
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
        fallbackTint: Color = WRhythmTheme.accent,
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
        self.fallbackTint = fallbackTint
        self.artworkSize = artworkSize
        self.isCurrent = isCurrent
        self.isPlaying = isPlaying
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: WRhythmSpacing.sm) {
            WRhythmArtworkThumbnail(
                coverArtId: coverArtId,
                fallbackSystemImage: fallbackSystemImage,
                tint: fallbackTint,
                size: artworkSize
            )

            VStack(alignment: .leading, spacing: WRhythmSpacing.xxs) {
                HStack(spacing: WRhythmSpacing.xs) {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker")
                            .font(WRhythmTypography.metadata)
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
        fallbackTint: Color = WRhythmTheme.accent,
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
            fallbackTint: fallbackTint,
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
            fallbackTint: tint,
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
                .font(WRhythmTypography.metadata)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(WRhythmTypography.controlLabelEmphasis)
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
                .font(WRhythmTypography.metadataEmphasis)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(tint)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

enum WRhythmFavoriteButtonSize {
    case row
    case action
    case watch

    var diameter: CGFloat {
        switch self {
        case .row:
            32
        case .action:
            36
        case .watch:
            28
        }
    }

    var iconFont: Font {
        switch self {
        case .row, .watch:
            WRhythmTypography.metadataEmphasis
        case .action:
            WRhythmTypography.featureTitle
        }
    }

    var badgeDiameter: CGFloat {
        switch self {
        case .row, .watch:
            10
        case .action:
            12
        }
    }
}

struct WRhythmFavoriteButton: View {
    let isFavorite: Bool
    var size: WRhythmFavoriteButtonSize = .action
    var isBusy = false
    let action: () async -> Void
    @State private var isRunningAction = false

    var body: some View {
        let isDisabled = AsyncActionPresentationPolicy.isDisabled(
            isRunning: isRunningAction,
            isExternallyBusy: isBusy
        )

        Button {
            guard !isDisabled else { return }
            isRunningAction = true
            Task {
                await action()
                await MainActor.run {
                    isRunningAction = false
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(size.iconFont)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isFavorite ? WRhythmTheme.favorite : .secondary)
                    .frame(width: size.diameter, height: size.diameter)
                    .background(buttonBackground, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isFavorite ? WRhythmTheme.favorite.opacity(0.75) : Color.secondary.opacity(0.24),
                                lineWidth: isFavorite ? 1.5 : 1
                            )
                    }

                if isFavorite {
                    Image(systemName: "checkmark")
                        .font(.system(size: size.badgeDiameter * 0.58, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: size.badgeDiameter, height: size.badgeDiameter)
                        .background(WRhythmTheme.favorite, in: Circle())
                        .offset(x: 1, y: 1)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(AsyncActionPresentationPolicy.opacity(isDisabled: isDisabled))
        .accessibilityLabel(isFavorite ? "Unfavorite" : "Favorite")
        .accessibilityValue(isFavorite ? "Favorited" : "Not favorited")
    }

    private var buttonBackground: some ShapeStyle {
        if isFavorite {
            return AnyShapeStyle(WRhythmTheme.favorite.opacity(0.24))
        } else {
            return AnyShapeStyle(.regularMaterial)
        }
    }
}

struct AsyncActionPresentationPolicy: Sendable {
    static func isDisabled(
        isRunning: Bool,
        isExternallyBusy: Bool = false,
        isUnavailable: Bool = false
    ) -> Bool {
        isRunning || isExternallyBusy || isUnavailable
    }

    static func opacity(isDisabled: Bool) -> Double {
        isDisabled ? 0.55 : 1
    }
}

struct PlaylistGenerationActionPolicy: Sendable {
    static func canStart(isGenerating: Bool, hasRequiredSelection: Bool) -> Bool {
        !isGenerating && hasRequiredSelection
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
            .modifier(WRhythmTopNavigationInset())
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

#if os(iOS)
private struct WRhythmTopNavigationInset: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top) {
            if horizontalSizeClass == .regular {
                Color.clear.frame(height: WRhythmVisual.topNavigationClearance)
            }
        }
    }
}
#endif

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
               let coverURL = StoredAlbumArtworkCache.displayURL(for: coverArtId, size: 120) {
                CachedAsyncImage(url: coverURL, storedCoverArtId: coverArtId) { image in
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
        .font(WRhythmTypography.metadata)
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
    var tint: Color = WRhythmTheme.accent
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous)
                .fill(.thinMaterial)

            if let artworkURL {
                CachedAsyncImage(url: artworkURL, storedCoverArtId: coverArtId) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                LinearGradient(
                    colors: [
                        tint.opacity(colorScheme == .dark ? 0.24 : 0.18),
                        WRhythmTheme.secondaryAccent.opacity(colorScheme == .dark ? 0.16 : 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: fallbackSystemImage)
                    .font(.system(size: max(16, size * 0.38), weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WRhythmVisual.thumbnailCornerRadius, style: .continuous)
                .strokeBorder(WRhythmTheme.surfaceStroke(for: colorScheme), lineWidth: 1)
        }
    }

    private var artworkURL: URL? {
        guard let coverArtId else { return nil }
        if let localURL = StoredAlbumArtworkCache.localURLIfExists(for: coverArtId) {
            return localURL
        }
        return StoredAlbumArtworkCache.displayURL(for: coverArtId, size: Int(size * 3))
    }
}

struct WRhythmEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemImage: String
    let title: String
    let message: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

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
                    .font(WRhythmTypography.featureTitle)
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if actionTitle != nil || secondaryActionTitle != nil {
                HStack(spacing: WRhythmSpacing.xs) {
                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderedProminent)
                    }

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                    }
                }
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
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var message: String?
    var systemImage = "arrow.triangle.2.circlepath"

    init(systemImage: String = "arrow.triangle.2.circlepath", title: String, message: String?) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

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
                    .font(WRhythmTypography.featureTitle)
                    .multilineTextAlignment(.center)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(WRhythmTypography.rowSubtitle)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            ProgressView()
                .tint(WRhythmTheme.accent)
                .padding(.top, WRhythmSpacing.xs)
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

struct WRhythmAppLoadingView: View {
    var body: some View {
        Image("WRhythmLogoYellow")
            .resizable()
            .scaledToFit()
            .frame(width: logoSize, height: logoSize)
            .accessibilityLabel("WRhythm")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .wrhythmPageBackground()
    }

    private var logoSize: CGFloat {
#if os(watchOS)
        48
#else
        64
#endif
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
            action: action,
            secondaryActionTitle: copyActionTitle,
            secondaryAction: copyAction
        )
    }

    private var copyActionTitle: String? {
#if os(macOS) || os(iOS)
        "Copy Error"
#else
        nil
#endif
    }

    private var copyAction: (() -> Void)? {
#if os(macOS) || os(iOS)
        {
            WRhythmClipboard.copy(
                WRhythmErrorCopyPolicy.copyText(title: title, message: message)
            )
        }
#else
        nil
#endif
    }
}

enum WRhythmErrorCopyPolicy: Sendable {
    static func copyText(
        title: String,
        message: String?,
        technicalDetails: String? = nil,
        recoverySuggestion: String? = nil
    ) -> String {
        [
            title,
            message,
            technicalDetails.map { "Details:\n\($0)" },
            recoverySuggestion.map { "Recovery:\n\($0)" }
        ]
        .compactMap { text -> String? in
            guard let text else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n\n")
    }
}

#if os(macOS) || os(iOS)
enum WRhythmClipboard {
    static func copy(_ value: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
#elseif os(iOS)
        UIPasteboard.general.string = value
#endif
    }
}
#endif

struct WRhythmActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: WRhythmSpacing.xs) {
            content
        }
        .padding(.horizontal, WRhythmSpacing.sm)
        .padding(.vertical, WRhythmSpacing.xs)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal)
        .padding(.vertical, WRhythmSpacing.xs)
    }
}

struct WRhythmSearchToolbarButton: View {
    let hasQuery: Bool
    let clear: () -> Void
    let search: () -> Void

    var body: some View {
        Button(action: hasQuery ? clear : search) {
            Image(systemName: hasQuery ? "xmark.circle.fill" : "magnifyingglass")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(hasQuery ? .secondary : WRhythmTheme.accent)
        }
        .accessibilityLabel(hasQuery ? "Clear search" : "Search")
    }
}
