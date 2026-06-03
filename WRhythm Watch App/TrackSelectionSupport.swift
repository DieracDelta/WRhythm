//
//  TrackSelectionSupport.swift
//  WRhythm Watch App
//
//  Selection and drag helpers for desktop track rows.
//

import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct TrackSelectionModifiers: OptionSet, Sendable {
    let rawValue: Int

    static let shift = TrackSelectionModifiers(rawValue: 1 << 0)
    static let command = TrackSelectionModifiers(rawValue: 1 << 1)

    var shouldSelectInsteadOfActivate: Bool {
        contains(.shift) || contains(.command)
    }
}

struct TrackSelectionState: Equatable, Sendable {
    var selectedIDs: Set<String> = []
    var anchorID: String?
}

enum TrackSelectionPolicy {
    static func applyClick(
        songID: String,
        orderedIDs: [String],
        currentState: TrackSelectionState,
        modifiers: TrackSelectionModifiers
    ) -> TrackSelectionState {
        if modifiers.contains(.shift) {
            guard let anchorID = currentState.anchorID,
                  let anchorIndex = orderedIDs.firstIndex(of: anchorID),
                  let songIndex = orderedIDs.firstIndex(of: songID) else {
                return TrackSelectionState(selectedIDs: [songID], anchorID: songID)
            }

            let bounds = min(anchorIndex, songIndex)...max(anchorIndex, songIndex)
            let rangeIDs = Set(orderedIDs[bounds])
            if modifiers.contains(.command) {
                return TrackSelectionState(
                    selectedIDs: currentState.selectedIDs.union(rangeIDs),
                    anchorID: anchorID
                )
            }
            return TrackSelectionState(selectedIDs: rangeIDs, anchorID: anchorID)
        }

        if modifiers.contains(.command) {
            var selectedIDs = currentState.selectedIDs
            if selectedIDs.contains(songID) {
                selectedIDs.remove(songID)
            } else {
                selectedIDs.insert(songID)
            }
            return TrackSelectionState(selectedIDs: selectedIDs, anchorID: songID)
        }

        return TrackSelectionState(selectedIDs: [songID], anchorID: songID)
    }
}

@MainActor
final class TrackSelectionManager: ObservableObject {
    static let shared = TrackSelectionManager()

    @Published private(set) var state = TrackSelectionState()

    private var songsByID: [String: Song] = [:]
    private var selectionOrder: [String] = []

    var selectedCount: Int {
        state.selectedIDs.count
    }

    func handleClick(song: Song, scopeSongs: [Song], modifiers: TrackSelectionModifiers) {
        let scope = scopeSongs.isEmpty ? [song] : scopeSongs
        for scopeSong in scope {
            songsByID[scopeSong.id] = scopeSong
        }
        songsByID[song.id] = song

        let nextState = TrackSelectionPolicy.applyClick(
            songID: song.id,
            orderedIDs: scope.map(\.id),
            currentState: state,
            modifiers: modifiers
        )
        state = nextState
        selectionOrder = selectionOrder(for: nextState.selectedIDs, preferredScope: scope)
    }

    func clear() {
        state = TrackSelectionState()
        selectionOrder = []
    }

    func isSelected(_ song: Song) -> Bool {
        state.selectedIDs.contains(song.id)
    }

    func selectedSongs(containing song: Song) -> [Song] {
        guard state.selectedIDs.contains(song.id), state.selectedIDs.count > 1 else {
            return [song]
        }
        let orderedSongs = selectionOrder.compactMap { songsByID[$0] }
        return orderedSongs.isEmpty ? [song] : orderedSongs
    }

    private func selectionOrder(for selectedIDs: Set<String>, preferredScope: [Song]) -> [String] {
        let scopedOrder = preferredScope.map(\.id).filter { selectedIDs.contains($0) }
        let retainedOrder = selectionOrder.filter { selectedIDs.contains($0) && !scopedOrder.contains($0) }
        let remainder = selectedIDs
            .filter { !scopedOrder.contains($0) && !retainedOrder.contains($0) }
            .sorted()
        return scopedOrder + retainedOrder + remainder
    }
}

enum TrackDragPayloadPolicy {
    static let contentType = UTType(exportedAs: "com.restivollc.wrhythm.songs")

    static func songsForDrag(startingAt song: Song, selectedSongs: [Song]) -> [Song] {
        if selectedSongs.contains(where: { $0.id == song.id }) {
            return selectedSongs
        }
        return [song]
    }

    static func encode(_ songs: [Song]) throws -> Data {
        try JSONEncoder().encode(songs)
    }

    static func decode(_ data: Data) throws -> [Song] {
        try JSONDecoder().decode([Song].self, from: data)
    }

    static func itemProvider(for songs: [Song]) -> NSItemProvider {
        let provider = NSItemProvider()
        guard let data = try? encode(songs) else { return provider }
        provider.registerDataRepresentation(
            forTypeIdentifier: contentType.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

#if os(macOS)
extension TrackSelectionModifiers {
    static var currentEventModifiers: TrackSelectionModifiers {
        let eventFlags = NSEvent.modifierFlags
        var modifiers: TrackSelectionModifiers = []
        if eventFlags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if eventFlags.contains(.command) {
            modifiers.insert(.command)
        }
        return modifiers
    }
}
#endif

extension View {
    func wrhythmSelectableTrack(song: Song, selectionScopeSongs: [Song]) -> some View {
        modifier(WRhythmSelectableTrackModifier(song: song, selectionScopeSongs: selectionScopeSongs))
    }
}

private struct WRhythmSelectableTrackModifier: ViewModifier {
    let song: Song
    let selectionScopeSongs: [Song]

    @ObservedObject private var selectionManager = TrackSelectionManager.shared

    func body(content: Content) -> some View {
#if os(macOS)
        let isSelected = selectionManager.isSelected(song)
        content
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(WRhythmTheme.accent.opacity(0.16))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(WRhythmTheme.accent.opacity(0.65), lineWidth: 1)
                }
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(WRhythmTheme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
            }
            .onDrag {
                let dragSongs = TrackDragPayloadPolicy.songsForDrag(
                    startingAt: song,
                    selectedSongs: selectionManager.selectedSongs(containing: song)
                )
                return TrackDragPayloadPolicy.itemProvider(for: dragSongs)
            }
#else
        content
#endif
    }
}
