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
}
