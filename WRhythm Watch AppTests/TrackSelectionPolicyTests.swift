//
//  TrackSelectionPolicyTests.swift
//  WRhythm Watch AppTests
//

import Testing
@testable import WRhythm_Watch_App

struct TrackSelectionPolicyTests {
    @Test func commandClickTogglesOneTrackAndUpdatesAnchor() {
        let state = TrackSelectionPolicy.applyClick(
            songID: "b",
            orderedIDs: ["a", "b", "c"],
            currentState: TrackSelectionState(selectedIDs: ["a"], anchorID: "a"),
            modifiers: [.command]
        )

        #expect(state.selectedIDs == ["a", "b"])
        #expect(state.anchorID == "b")

        let toggledOff = TrackSelectionPolicy.applyClick(
            songID: "b",
            orderedIDs: ["a", "b", "c"],
            currentState: state,
            modifiers: [.command]
        )

        #expect(toggledOff.selectedIDs == ["a"])
        #expect(toggledOff.anchorID == "b")
    }

    @Test func shiftClickSelectsInclusiveRangeFromAnchor() {
        let state = TrackSelectionPolicy.applyClick(
            songID: "d",
            orderedIDs: ["a", "b", "c", "d", "e"],
            currentState: TrackSelectionState(selectedIDs: ["b"], anchorID: "b"),
            modifiers: [.shift]
        )

        #expect(state.selectedIDs == ["b", "c", "d"])
        #expect(state.anchorID == "b")
    }

    @Test func shiftCommandClickAddsRangeToExistingSelection() {
        let state = TrackSelectionPolicy.applyClick(
            songID: "e",
            orderedIDs: ["a", "b", "c", "d", "e"],
            currentState: TrackSelectionState(selectedIDs: ["a", "c"], anchorID: "c"),
            modifiers: [.shift, .command]
        )

        #expect(state.selectedIDs == ["a", "c", "d", "e"])
        #expect(state.anchorID == "c")
    }

    @Test func shiftClickWithoutUsableAnchorSelectsCurrentTrackOnly() {
        let state = TrackSelectionPolicy.applyClick(
            songID: "b",
            orderedIDs: ["a", "b", "c"],
            currentState: TrackSelectionState(selectedIDs: ["z"], anchorID: "z"),
            modifiers: [.shift]
        )

        #expect(state.selectedIDs == ["b"])
        #expect(state.anchorID == "b")
    }

    @Test func dragUsesSelectedTracksOnlyWhenDraggedRowIsSelected() {
        let first = makeSong(id: "a", title: "A")
        let second = makeSong(id: "b", title: "B")
        let third = makeSong(id: "c", title: "C")

        #expect(TrackDragPayloadPolicy.songsForDrag(
            startingAt: second,
            selectedSongs: [first, second]
        ).map(\.id) == ["a", "b"])

        #expect(TrackDragPayloadPolicy.songsForDrag(
            startingAt: third,
            selectedSongs: [first, second]
        ).map(\.id) == ["c"])
    }

    @Test func dragPayloadRoundTripsSongs() throws {
        let songs = [
            makeSong(id: "a", title: "A"),
            makeSong(id: "b", title: "B")
        ]

        let data = try TrackDragPayloadPolicy.encode(songs)
        let decoded = try TrackDragPayloadPolicy.decode(data)

        #expect(decoded.map(\.id) == ["a", "b"])
        #expect(decoded.map(\.title) == ["A", "B"])
    }

    private func makeSong(id: String, title: String) -> Song {
        Song(
            id: id,
            title: title,
            album: "Album",
            albumId: nil,
            artist: "Artist",
            artistId: nil,
            track: nil,
            year: nil,
            genre: nil,
            coverArt: nil,
            size: nil,
            contentType: nil,
            suffix: nil,
            duration: nil,
            bitRate: nil,
            path: nil
        )
    }
}
