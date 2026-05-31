//
//  SongRenderWindowPolicyTests.swift
//  WRhythm Watch AppTests
//

import Testing
@testable import WRhythm_Watch_App

struct SongRenderWindowPolicyTests {
    @Test func zeroMeansUnlimited() {
        #expect(SongRenderWindowPolicy.effectiveLimit(0) == nil)
        #expect(SongRenderWindowPolicy.visibleRange(totalCount: 1_000, anchorIndex: 500, storedLimit: 0) == 0..<1_000)
    }

    @Test func finiteLimitsAreClampedToMinimum() {
        #expect(SongRenderWindowPolicy.sanitizeLimit(-5) == 20)
        #expect(SongRenderWindowPolicy.sanitizeLimit(1) == 20)
        #expect(SongRenderWindowPolicy.sanitizeLimit(19) == 20)
        #expect(SongRenderWindowPolicy.sanitizeLimit(20) == 20)
        #expect(SongRenderWindowPolicy.sanitizeLimit(500) == 500)
    }

    @Test func visibleRangeCentersAroundAnchorWhenPossible() {
        let range = SongRenderWindowPolicy.visibleRange(totalCount: 1_000, anchorIndex: 500, storedLimit: 100)

        #expect(range == 450..<550)
    }

    @Test func visibleRangeClampsNearStartAndEnd() {
        let startRange = SongRenderWindowPolicy.visibleRange(totalCount: 1_000, anchorIndex: 5, storedLimit: 100)
        let endRange = SongRenderWindowPolicy.visibleRange(totalCount: 1_000, anchorIndex: 995, storedLimit: 100)

        #expect(startRange == 0..<100)
        #expect(endRange == 900..<1_000)
    }

    @Test func visibleRangeUsesFullCollectionWhenLimitExceedsCount() {
        let range = SongRenderWindowPolicy.visibleRange(totalCount: 12, anchorIndex: 8, storedLimit: 100)

        #expect(range == 0..<12)
    }

    @Test func emptyCollectionsHaveEmptyRange() {
        let range = SongRenderWindowPolicy.visibleRange(totalCount: 0, anchorIndex: 0, storedLimit: 100)

        #expect(range == 0..<0)
    }

    @Test func hiddenRowsUseSmallScrollSentinelInsteadOfLargeBlankSpacer() {
        #expect(SongRenderWindowPolicy.hiddenSpacerRows(hiddenRows: 0, storedLimit: 50) == 0)
        #expect(SongRenderWindowPolicy.hiddenSpacerRows(hiddenRows: 1, storedLimit: 50) == 1)
        #expect(SongRenderWindowPolicy.hiddenSpacerRows(hiddenRows: 500, storedLimit: 50) == 1)
    }

    @Test func spacerAppearanceMovesAnchorByPageInsteadOfSingleRow() {
        let range = 100..<150

        #expect(SongRenderWindowPolicy.anchorAfterTopSpacerAppears(visibleRange: range, storedLimit: 50) == 75)
        #expect(SongRenderWindowPolicy.anchorAfterBottomSpacerAppears(visibleRange: range, totalCount: 300, storedLimit: 50) == 175)
    }

    @Test func pagedWindowLoadsPagesAroundAnchorAndEvictsDistantPages() {
        let visiblePages = SongRenderWindowPolicy.visiblePageIndices(
            totalCount: 1_000,
            anchorIndex: 525,
            storedLimit: 100,
            pageSize: 25,
            retainedPageRadius: 1
        )
        let retainedPages = SongRenderWindowPolicy.retainedPageIndices(
            visiblePageIndices: visiblePages,
            totalCount: 1_000,
            pageSize: 25,
            retainedPageRadius: 1
        )

        #expect(visiblePages == Set([19, 20, 21, 22]))
        #expect(retainedPages == Set([18, 19, 20, 21, 22, 23]))
    }

    @Test func pagedWindowProducesPlaceholderSlotsForUnloadedPages() {
        let slots = SongRenderWindowPolicy.renderSlots(
            totalCount: 200,
            anchorIndex: 60,
            storedLimit: 60,
            pageSize: 20,
            loadedPageIndices: [3]
        )

        #expect(slots.count == 60)
        #expect(slots.filter(\.isLoaded).map(\.index) == Array(60..<80))
        #expect(slots.filter { !$0.isLoaded }.count == 40)
    }

    @Test func pagedWindowNeverRendersMoreThanTheConfiguredLimit() {
        let slots = SongRenderWindowPolicy.renderSlots(
            totalCount: 10_000,
            anchorIndex: 9_900,
            storedLimit: 50,
            pageSize: 25,
            loadedPageIndices: Set(0..<400)
        )

        #expect(slots.count == 50)
        #expect(slots.first?.index == 9_875)
        #expect(slots.last?.index == 9_924)
    }

    @Test func largeClientCollectionsRenderOnlyConfiguredWindow() {
        let totalArtistCount = 2_362
        let slots = SongRenderWindowPolicy.renderSlots(
            totalCount: totalArtistCount,
            anchorIndex: 1_200,
            storedLimit: 50,
            pageSize: 25,
            loadedPageIndices: [48]
        )

        #expect(slots.count == 50)
        #expect(slots.map(\.index) == Array(1_175..<1_225))
        #expect(slots.filter(\.isLoaded).map(\.index) == Array(1_200..<1_225))
        #expect(slots.filter { !$0.isLoaded }.count == 25)
    }

    @Test func resetTokenChangesWhenSortQueryOrScopeChanges() {
        let baseline = SongRenderWindowPolicy.resetToken(scope: "albums", sortIdentifier: "title", query: "queen")

        #expect(SongRenderWindowPolicy.resetToken(scope: "albums", sortIdentifier: "title", query: "queen") == baseline)
        #expect(SongRenderWindowPolicy.resetToken(scope: "albums", sortIdentifier: "title", query: " queen ") == baseline)
        #expect(SongRenderWindowPolicy.resetToken(scope: "albums", sortIdentifier: "artist", query: "queen") != baseline)
        #expect(SongRenderWindowPolicy.resetToken(scope: "albums", sortIdentifier: "title", query: "abba") != baseline)
        #expect(SongRenderWindowPolicy.resetToken(scope: "artists", sortIdentifier: "title", query: "queen") != baseline)
    }

    @Test func trackSearchResetTokenChangesWhenModeOrQueryChanges() {
        let baseline = SongRenderWindowPolicy.trackSearchResetToken(mode: "online", query: "blondie")

        #expect(SongRenderWindowPolicy.trackSearchResetToken(mode: "online", query: "blondie") == baseline)
        #expect(SongRenderWindowPolicy.trackSearchResetToken(mode: "online", query: " blondie ") == baseline)
        #expect(SongRenderWindowPolicy.trackSearchResetToken(mode: "offline", query: "blondie") != baseline)
        #expect(SongRenderWindowPolicy.trackSearchResetToken(mode: "online", query: "abba") != baseline)
    }

    @Test func searchResultGroupResetTokenChangesWhenModeKindOrQueryChanges() {
        let baseline = SongRenderWindowPolicy.searchResultGroupResetToken(
            mode: "online",
            kind: "artists",
            query: "blondie"
        )

        #expect(
            SongRenderWindowPolicy.searchResultGroupResetToken(mode: "online", kind: "artists", query: "blondie")
                == baseline
        )
        #expect(
            SongRenderWindowPolicy.searchResultGroupResetToken(mode: "online", kind: "artists", query: " blondie ")
                == baseline
        )
        #expect(
            SongRenderWindowPolicy.searchResultGroupResetToken(mode: "offline", kind: "artists", query: "blondie")
                != baseline
        )
        #expect(
            SongRenderWindowPolicy.searchResultGroupResetToken(mode: "online", kind: "albums", query: "blondie")
                != baseline
        )
        #expect(
            SongRenderWindowPolicy.searchResultGroupResetToken(mode: "online", kind: "artists", query: "abba")
                != baseline
        )
    }

    @Test func artistAlbumResetTokenChangesWhenArtistOrModeChanges() {
        let baseline = SongRenderWindowPolicy.artistAlbumResetToken(artistId: "artist-1", mode: "online")

        #expect(SongRenderWindowPolicy.artistAlbumResetToken(artistId: "artist-1", mode: "online") == baseline)
        #expect(SongRenderWindowPolicy.artistAlbumResetToken(artistId: "artist-1", mode: "offline") != baseline)
        #expect(SongRenderWindowPolicy.artistAlbumResetToken(artistId: "artist-2", mode: "online") != baseline)
    }

    @Test func playlistGenQueueResetTokenChangesWhenQueueIdentityOrOrderChanges() {
        let baseline = SongRenderWindowPolicy.playlistGenQueueResetToken(songIds: ["song-1", "song-2", "song-3"])

        #expect(SongRenderWindowPolicy.playlistGenQueueResetToken(songIds: ["song-1", "song-2", "song-3"]) == baseline)
        #expect(SongRenderWindowPolicy.playlistGenQueueResetToken(songIds: ["song-1", "song-3", "song-2"]) != baseline)
        #expect(SongRenderWindowPolicy.playlistGenQueueResetToken(songIds: ["song-1", "song-2"]) != baseline)
        #expect(SongRenderWindowPolicy.playlistGenQueueResetToken(songIds: ["song-1", "song-2", "song-4"]) != baseline)
    }

    @Test func downloadedRadioPlaylistsResetTokenChangesWhenPlaylistIdentityOrOrderChanges() {
        let baseline = SongRenderWindowPolicy.downloadedRadioPlaylistsResetToken(
            playlistIds: ["radio-1", "radio-2", "radio-3"]
        )

        #expect(
            SongRenderWindowPolicy.downloadedRadioPlaylistsResetToken(playlistIds: ["radio-1", "radio-2", "radio-3"])
                == baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedRadioPlaylistsResetToken(playlistIds: ["radio-1", "radio-3", "radio-2"])
                != baseline
        )
        #expect(SongRenderWindowPolicy.downloadedRadioPlaylistsResetToken(playlistIds: ["radio-1", "radio-2"]) != baseline)
        #expect(
            SongRenderWindowPolicy.downloadedRadioPlaylistsResetToken(playlistIds: ["radio-1", "radio-2", "radio-4"])
                != baseline
        )
    }

    @Test func availableTracksResetTokenChangesWhenSongIdentityOrOrderChanges() {
        let baseline = SongRenderWindowPolicy.availableTracksResetToken(songIds: ["song-1", "song-2", "song-3"])

        #expect(SongRenderWindowPolicy.availableTracksResetToken(songIds: ["song-1", "song-2", "song-3"]) == baseline)
        #expect(SongRenderWindowPolicy.availableTracksResetToken(songIds: ["song-1", "song-3", "song-2"]) != baseline)
        #expect(SongRenderWindowPolicy.availableTracksResetToken(songIds: ["song-1", "song-2"]) != baseline)
        #expect(SongRenderWindowPolicy.availableTracksResetToken(songIds: ["song-1", "song-2", "song-4"]) != baseline)
    }

    @Test func prebufferDownloadStatusesResetTokenChangesWhenStatusIdentityOrOrderChanges() {
        let baseline = SongRenderWindowPolicy.prebufferDownloadStatusesResetToken(
            statusIds: ["song-1", "song-2", "song-3"]
        )

        #expect(
            SongRenderWindowPolicy.prebufferDownloadStatusesResetToken(statusIds: ["song-1", "song-2", "song-3"])
                == baseline
        )
        #expect(
            SongRenderWindowPolicy.prebufferDownloadStatusesResetToken(statusIds: ["song-1", "song-3", "song-2"])
                != baseline
        )
        #expect(SongRenderWindowPolicy.prebufferDownloadStatusesResetToken(statusIds: ["song-1", "song-2"]) != baseline)
        #expect(
            SongRenderWindowPolicy.prebufferDownloadStatusesResetToken(statusIds: ["song-1", "song-2", "song-4"])
            != baseline
        )
    }

    @Test func downloadedAlbumSectionsResetTokenChangesWhenAlbumIdentityOrderOrQueryChanges() {
        let baseline = SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
            albumSectionIds: ["album-1", "album-2", "album-3"],
            query: "darren"
        )

        #expect(
            SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
                albumSectionIds: ["album-1", "album-2", "album-3"],
                query: "darren"
            ) == baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
                albumSectionIds: ["album-1", "album-2", "album-3"],
                query: " darren "
            ) == baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
                albumSectionIds: ["album-1", "album-3", "album-2"],
                query: "darren"
            ) != baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
                albumSectionIds: ["album-1", "album-2"],
                query: "darren"
            ) != baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
                albumSectionIds: ["album-1", "album-2", "album-4"],
                query: "darren"
            ) != baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSectionsResetToken(
                albumSectionIds: ["album-1", "album-2", "album-3"],
                query: "blondie"
            ) != baseline
        )
    }

    @Test func downloadedAlbumSongsResetTokenChangesWhenAlbumOrSongIdentityChanges() {
        let baseline = SongRenderWindowPolicy.downloadedAlbumSongsResetToken(
            albumSectionId: "album-1",
            songIds: ["song-1", "song-2", "song-3"]
        )

        #expect(
            SongRenderWindowPolicy.downloadedAlbumSongsResetToken(
                albumSectionId: "album-1",
                songIds: ["song-1", "song-2", "song-3"]
            ) == baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSongsResetToken(
                albumSectionId: "album-2",
                songIds: ["song-1", "song-2", "song-3"]
            ) != baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSongsResetToken(
                albumSectionId: "album-1",
                songIds: ["song-1", "song-3", "song-2"]
            ) != baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSongsResetToken(
                albumSectionId: "album-1",
                songIds: ["song-1", "song-2"]
            ) != baseline
        )
        #expect(
            SongRenderWindowPolicy.downloadedAlbumSongsResetToken(
                albumSectionId: "album-1",
                songIds: ["song-1", "song-2", "song-4"]
            ) != baseline
        )
    }

    @Test func sidebarQueueResetTokenChangesWhenQueueIdentityOrOrderChanges() {
        let baseline = SongRenderWindowPolicy.sidebarQueueResetToken(songIds: ["song-1", "song-2", "song-3"])

        #expect(SongRenderWindowPolicy.sidebarQueueResetToken(songIds: ["song-1", "song-2", "song-3"]) == baseline)
        #expect(SongRenderWindowPolicy.sidebarQueueResetToken(songIds: ["song-1", "song-3", "song-2"]) != baseline)
        #expect(SongRenderWindowPolicy.sidebarQueueResetToken(songIds: ["song-1", "song-2"]) != baseline)
        #expect(SongRenderWindowPolicy.sidebarQueueResetToken(songIds: ["song-1", "song-2", "song-4"]) != baseline)
    }

    @Test func pagesToLoadOnlyRequestsMissingVisiblePages() {
        let pages = SongRenderWindowPolicy.pagesToLoad(
            totalCount: 1_000,
            anchorIndex: 300,
            storedLimit: 100,
            pageSize: 25,
            loadedPageIndices: [10, 11]
        )

        #expect(pages == [12, 13])
    }

    @Test func evictingLoadedPagesKeepsOnlyRetainedNeighborhood() {
        let retained = SongRenderWindowPolicy.loadedPageIndicesAfterEviction(
            loadedPageIndices: Set(0..<20),
            totalCount: 1_000,
            anchorIndex: 525,
            storedLimit: 100,
            pageSize: 25,
            retainedPageRadius: 1
        )

        #expect(retained == Set([18, 19]))
    }
}
