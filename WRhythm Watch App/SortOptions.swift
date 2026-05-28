import SwiftUI

protocol WRhythmSortOption: CaseIterable, Hashable, Identifiable {
    var title: String { get }
    var systemImage: String { get }
}

extension WRhythmSortOption {
    var id: Self { self }
}

struct WRhythmSortMenu<Option: WRhythmSortOption>: View where Option.AllCases: RandomAccessCollection, Option.AllCases.Element == Option {
    @Binding var selection: Option

    var body: some View {
#if os(watchOS)
        Picker(selection: $selection) {
            ForEach(Option.allCases) { option in
                Text(option.title)
                    .tag(option)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WRhythmTheme.accent)
        }
        .accessibilityLabel("Sort")
        .accessibilityValue(selection.title)
#else
        Menu {
            ForEach(Option.allCases) { option in
                Button {
                    selection = option
                } label: {
                    Label(option.title, systemImage: selection == option ? "checkmark" : option.systemImage)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WRhythmTheme.accent)
        }
        .accessibilityLabel("Sort")
        .accessibilityValue(selection.title)
#endif
    }
}

enum AlbumSortOption: String, WRhythmSortOption {
    case titleAscending
    case titleDescending
    case artistAscending
    case artistDescending
    case newest
    case mostTracks

    var title: String {
        switch self {
        case .titleAscending: "Title A-Z"
        case .titleDescending: "Title Z-A"
        case .artistAscending: "Artist A-Z"
        case .artistDescending: "Artist Z-A"
        case .newest: "Newest"
        case .mostTracks: "Most Tracks"
        }
    }

    var systemImage: String {
        switch self {
        case .titleAscending, .artistAscending: "textformat.abc"
        case .titleDescending, .artistDescending: "textformat.abc.dottedunderline"
        case .newest: "calendar"
        case .mostTracks: "number"
        }
    }

    func sorted(_ albums: [AlbumSummary]) -> [AlbumSummary] {
        albums.sorted { lhs, rhs in
            switch self {
            case .titleAscending:
                return localizedLess(lhs.name, rhs.name)
            case .titleDescending:
                return localizedLess(rhs.name, lhs.name)
            case .artistAscending:
                return localizedLess(lhs.artist ?? "", rhs.artist ?? "")
            case .artistDescending:
                return localizedLess(rhs.artist ?? "", lhs.artist ?? "")
            case .newest:
                let lhsYear = lhs.year ?? 0
                let rhsYear = rhs.year ?? 0
                if lhsYear != rhsYear {
                    return lhsYear > rhsYear
                }
                if lhs.created != rhs.created {
                    return lhs.created > rhs.created
                }
                return localizedLess(lhs.name, rhs.name)
            case .mostTracks:
                return lhs.songCount == rhs.songCount ? localizedLess(lhs.name, rhs.name) : lhs.songCount > rhs.songCount
            }
        }
    }
}

enum ArtistSortOption: String, WRhythmSortOption {
    case nameAscending
    case nameDescending
    case mostAlbums
    case fewestAlbums

    var title: String {
        switch self {
        case .nameAscending: "Name A-Z"
        case .nameDescending: "Name Z-A"
        case .mostAlbums: "Most Albums"
        case .fewestAlbums: "Fewest Albums"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAscending: "textformat.abc"
        case .nameDescending: "textformat.abc.dottedunderline"
        case .mostAlbums: "square.stack.3d.up"
        case .fewestAlbums: "square.stack.3d.down.right"
        }
    }

    func sorted(_ artists: [Artist]) -> [Artist] {
        artists.sorted { lhs, rhs in
            switch self {
            case .nameAscending:
                localizedLess(lhs.name, rhs.name)
            case .nameDescending:
                localizedLess(rhs.name, lhs.name)
            case .mostAlbums:
                (lhs.albumCount ?? 0) == (rhs.albumCount ?? 0) ? localizedLess(lhs.name, rhs.name) : (lhs.albumCount ?? 0) > (rhs.albumCount ?? 0)
            case .fewestAlbums:
                (lhs.albumCount ?? 0) == (rhs.albumCount ?? 0) ? localizedLess(lhs.name, rhs.name) : (lhs.albumCount ?? 0) < (rhs.albumCount ?? 0)
            }
        }
    }
}

enum PlaylistSortOption: String, WRhythmSortOption {
    case nameAscending
    case nameDescending
    case recentlyChanged
    case mostTracks
    case fewestTracks

    var title: String {
        switch self {
        case .nameAscending: "Name A-Z"
        case .nameDescending: "Name Z-A"
        case .recentlyChanged: "Recently Changed"
        case .mostTracks: "Most Tracks"
        case .fewestTracks: "Fewest Tracks"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAscending: "textformat.abc"
        case .nameDescending: "textformat.abc.dottedunderline"
        case .recentlyChanged: "clock.arrow.circlepath"
        case .mostTracks: "number"
        case .fewestTracks: "number.circle"
        }
    }

    func sorted(_ playlists: [PlaylistSummary]) -> [PlaylistSummary] {
        playlists.sorted { lhs, rhs in
            switch self {
            case .nameAscending:
                localizedLess(lhs.name, rhs.name)
            case .nameDescending:
                localizedLess(rhs.name, lhs.name)
            case .recentlyChanged:
                lhs.changed == rhs.changed ? localizedLess(lhs.name, rhs.name) : lhs.changed > rhs.changed
            case .mostTracks:
                lhs.songCount == rhs.songCount ? localizedLess(lhs.name, rhs.name) : lhs.songCount > rhs.songCount
            case .fewestTracks:
                lhs.songCount == rhs.songCount ? localizedLess(lhs.name, rhs.name) : lhs.songCount < rhs.songCount
            }
        }
    }
}

enum SongSortOption: String, WRhythmSortOption {
    case original
    case trackNumber
    case titleAscending
    case titleDescending
    case artistAscending
    case albumAscending
    case longest
    case shortest

    var title: String {
        switch self {
        case .original: "Original"
        case .trackNumber: "Track Number"
        case .titleAscending: "Title A-Z"
        case .titleDescending: "Title Z-A"
        case .artistAscending: "Artist A-Z"
        case .albumAscending: "Album A-Z"
        case .longest: "Longest"
        case .shortest: "Shortest"
        }
    }

    var systemImage: String {
        switch self {
        case .original: "line.3.horizontal"
        case .trackNumber: "number"
        case .titleAscending, .artistAscending, .albumAscending: "textformat.abc"
        case .titleDescending: "textformat.abc.dottedunderline"
        case .longest: "timer"
        case .shortest: "timer.circle"
        }
    }

    func sorted(_ songs: [Song]) -> [Song] {
        switch self {
        case .original:
            songs
        case .trackNumber:
            songs.sorted { lhs, rhs in
                let lhsTrack = lhs.track ?? Int.max
                let rhsTrack = rhs.track ?? Int.max
                return lhsTrack == rhsTrack ? localizedLess(lhs.title, rhs.title) : lhsTrack < rhsTrack
            }
        case .titleAscending:
            songs.sorted { localizedLess($0.title, $1.title) }
        case .titleDescending:
            songs.sorted { localizedLess($1.title, $0.title) }
        case .artistAscending:
            songs.sorted { lhs, rhs in localizedLess(lhs.artist ?? "", rhs.artist ?? "") }
        case .albumAscending:
            songs.sorted { lhs, rhs in localizedLess(lhs.album ?? "", rhs.album ?? "") }
        case .longest:
            songs.sorted { ($0.duration ?? 0) == ($1.duration ?? 0) ? localizedLess($0.title, $1.title) : ($0.duration ?? 0) > ($1.duration ?? 0) }
        case .shortest:
            songs.sorted { ($0.duration ?? 0) == ($1.duration ?? 0) ? localizedLess($0.title, $1.title) : ($0.duration ?? 0) < ($1.duration ?? 0) }
        }
    }
}

private func localizedLess(_ lhs: String, _ rhs: String) -> Bool {
    lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
}
