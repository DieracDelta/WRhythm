import Foundation

struct PagedCollectionCache<Element: Sendable>: Sendable {
    private let pageSize: Int
    private let maxLoadedPages: Int?
    private var pages: [Int: [Element]] = [:]

    private(set) var hasMoreAfter = true

    init(pageSize: Int, maxLoadedPages: Int?) {
        self.pageSize = max(1, pageSize)
        if let maxLoadedPages {
            self.maxLoadedPages = max(1, maxLoadedPages)
        } else {
            self.maxLoadedPages = nil
        }
    }

    var isEmpty: Bool {
        pages.isEmpty
    }

    var loadedPageIndices: [Int] {
        pages.keys.sorted()
    }

    var hasLoadedPreviousPage: Bool {
        guard let firstPageIndex = loadedPageIndices.first else { return false }
        return firstPageIndex > 0
    }

    var nextPageIndex: Int {
        guard let lastPageIndex = loadedPageIndices.last else { return 0 }
        return lastPageIndex + 1
    }

    var previousPageIndex: Int? {
        guard let firstPageIndex = loadedPageIndices.first, firstPageIndex > 0 else { return nil }
        return firstPageIndex - 1
    }

    var nextOffset: Int {
        nextPageIndex * pageSize
    }

    var elements: [Element] {
        loadedPageIndices.flatMap { pages[$0] ?? [] }
    }

    mutating func storePage(index: Int, elements: [Element], hasMoreAfterPage: Bool) {
        pages[max(0, index)] = elements
        if index >= nextPageIndex - 1 {
            hasMoreAfter = hasMoreAfterPage
        }
        pruneAround(pageIndex: max(0, index))
    }

    mutating func reset(keepingMaxLoadedPages maxLoadedPages: Int? = nil) {
        self = PagedCollectionCache(pageSize: pageSize, maxLoadedPages: maxLoadedPages ?? self.maxLoadedPages)
    }

    private mutating func pruneAround(pageIndex anchorPageIndex: Int) {
        guard let maxLoadedPages, pages.count > maxLoadedPages else { return }

        let retained = Set(
            pages.keys
                .sorted { lhs, rhs in
                    let lhsDistance = abs(lhs - anchorPageIndex)
                    let rhsDistance = abs(rhs - anchorPageIndex)
                    return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
                }
                .prefix(maxLoadedPages)
        )

        pages = pages.filter { retained.contains($0.key) }
    }
}
