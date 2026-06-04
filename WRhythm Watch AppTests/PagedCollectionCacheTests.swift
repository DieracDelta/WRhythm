import Testing
@testable import WRhythm_Watch_App

struct PagedCollectionCacheTests {
    @Test func appendingPagesKeepsOnlyBoundedPagesAroundNewestPage() {
        // Given
        var cache = PagedCollectionCache<Int>(pageSize: 2, maxLoadedPages: 3)

        // When
        cache.storePage(index: 0, elements: [0, 1], hasMoreAfterPage: true)
        cache.storePage(index: 1, elements: [2, 3], hasMoreAfterPage: true)
        cache.storePage(index: 2, elements: [4, 5], hasMoreAfterPage: true)
        cache.storePage(index: 3, elements: [6, 7], hasMoreAfterPage: true)

        // Then
        #expect(cache.loadedPageIndices == [1, 2, 3])
        #expect(cache.elements == [2, 3, 4, 5, 6, 7])
        #expect(cache.hasLoadedPreviousPage)
        #expect(cache.previousPageIndex == 0)
        #expect(cache.nextPageIndex == 4)
        #expect(cache.nextOffset == 8)
    }

    @Test func loadingPreviousPageKeepsWindowAroundPreviousPage() {
        // Given
        var cache = PagedCollectionCache<Int>(pageSize: 2, maxLoadedPages: 3)
        cache.storePage(index: 5, elements: [10, 11], hasMoreAfterPage: true)
        cache.storePage(index: 6, elements: [12, 13], hasMoreAfterPage: true)
        cache.storePage(index: 7, elements: [14, 15], hasMoreAfterPage: true)

        // When
        cache.storePage(index: 4, elements: [8, 9], hasMoreAfterPage: true)

        // Then
        #expect(cache.loadedPageIndices == [4, 5, 6])
        #expect(cache.elements == [8, 9, 10, 11, 12, 13])
        #expect(cache.previousPageIndex == 3)
    }

    @Test func unlimitedCacheRetainsAllPages() {
        // Given
        var cache = PagedCollectionCache<Int>(pageSize: 1, maxLoadedPages: nil)

        // When
        for index in 0..<10 {
            cache.storePage(index: index, elements: [index], hasMoreAfterPage: true)
        }

        // Then
        #expect(cache.loadedPageIndices == Array(0..<10))
        #expect(cache.elements == Array(0..<10))
    }

    @Test func albumMetadataCacheIsNotCappedByRenderedRowLimit() {
        // Given
        var cache = PagedCollectionCache<Int>(
            pageSize: 20,
            maxLoadedPages: AlbumMetadataPagingPolicy.maxLoadedPages(forRenderedLimit: 50)
        )

        // When
        for page in 0..<8 {
            let lowerBound = page * 20
            cache.storePage(
                index: page,
                elements: Array(lowerBound..<(lowerBound + 20)),
                hasMoreAfterPage: true
            )
        }

        // Then
        #expect(cache.loadedPageIndices == Array(0..<8))
        #expect(cache.elements.count == 160)
        #expect(cache.nextPageIndex == 8)
    }

    @Test func endOfPaginationIsTracked() {
        // Given
        var cache = PagedCollectionCache<Int>(pageSize: 2, maxLoadedPages: 3)

        // When
        cache.storePage(index: 0, elements: [0, 1], hasMoreAfterPage: true)
        cache.storePage(index: 1, elements: [2], hasMoreAfterPage: false)

        // Then
        #expect(cache.hasMoreAfter == false)
        #expect(cache.nextPageIndex == 2)
    }
}
