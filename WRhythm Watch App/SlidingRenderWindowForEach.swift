import SwiftUI

struct SlidingRenderWindowForEach<Element, Row: View>: View {
    private let items: [Element]
    private let estimatedRowHeight: CGFloat
    private let spacing: CGFloat
    private let resetToken: AnyHashable
    private let anchorIndexHint: Int
    private let renderMode: SongRenderWindowPolicy.RenderMode
    private let row: (Int, Element) -> Row

    @AppStorage(SongRenderWindowPolicy.userDefaultsKey) private var storedLimit = SongRenderWindowPolicy.defaultLimit
    @State private var anchorIndex = 0
    @State private var loadedPageIndices: Set<Int> = []
    @State private var pendingPageIndices: Set<Int> = []

    init(
        _ items: [Element],
        estimatedRowHeight: CGFloat = 64,
        spacing: CGFloat = 0,
        resetToken: some Hashable = 0,
        anchorIndexHint: Int = 0,
        renderMode: SongRenderWindowPolicy.RenderMode = .paged,
        @ViewBuilder row: @escaping (Int, Element) -> Row
    ) {
        self.items = items
        self.estimatedRowHeight = estimatedRowHeight
        self.spacing = spacing
        self.resetToken = AnyHashable(resetToken)
        self.anchorIndexHint = anchorIndexHint
        self.renderMode = renderMode
        self.row = row
    }

    private var visibleRange: Range<Int> {
        SongRenderWindowPolicy.visibleRange(
            totalCount: items.count,
            anchorIndex: anchorIndex,
            storedLimit: storedLimit
        )
    }

    private var renderSlots: [SongRenderWindowPolicy.RenderSlot] {
        switch renderMode {
        case .paged:
            return SongRenderWindowPolicy.pagedRenderSlots(
                totalCount: items.count,
                storedLimit: storedLimit,
                loadedPageIndices: loadedPageIndices,
                pendingPageIndices: pendingPageIndices
            )
        case .slidingWindow, .fullRangeLoaded:
            return SongRenderWindowPolicy.renderSlots(
                totalCount: items.count,
                anchorIndex: anchorIndex,
                storedLimit: storedLimit,
                loadedPageIndices: loadedPageIndices,
                renderMode: renderMode
            )
        }
    }

    var body: some View {
        LazyVStack(spacing: spacing) {
            if renderMode == .paged,
               let previousPage = SongRenderWindowPolicy.previousPageIndexToLoad(
                    storedLimit: storedLimit,
                    loadedPageIndices: loadedPageIndices,
                    pendingPageIndices: pendingPageIndices
               ) {
                Button(action: {
                    loadPages([previousPage])
                }) {
                    loadingSentinel(title: "Load earlier")
                }
                .buttonStyle(.plain)
            }

            if renderMode == .slidingWindow, visibleRange.lowerBound > 0 {
                loadingSentinel(title: "Loading earlier")
                    .frame(height: spacerHeight(for: visibleRange.lowerBound))
                    .onAppear {
                        anchorIndex = SongRenderWindowPolicy.anchorAfterTopSpacerAppears(
                            visibleRange: visibleRange,
                            storedLimit: storedLimit
                        )
                        scheduleVisiblePages()
                    }
            }

            ForEach(renderSlots) { slot in
                if slot.isLoaded, slot.index < items.count {
                    row(slot.index, items[slot.index])
                        .onAppear {
                            updateAnchorIfNeeded(for: slot.index)
                        }
                } else {
                    loadingPlaceholder(index: slot.index)
                        .onAppear {
                            updateAnchorIfNeeded(for: slot.index)
                            scheduleVisiblePages()
                        }
                }
            }

            if renderMode == .slidingWindow, visibleRange.upperBound < items.count {
                loadingSentinel(title: "Loading more")
                    .frame(height: spacerHeight(for: items.count - visibleRange.upperBound))
                    .onAppear {
                        anchorIndex = SongRenderWindowPolicy.anchorAfterBottomSpacerAppears(
                            visibleRange: visibleRange,
                            totalCount: items.count,
                            storedLimit: storedLimit
                        )
                        scheduleVisiblePages()
                    }
            }

            if renderMode == .paged,
               let nextPage = SongRenderWindowPolicy.nextPageIndexToLoad(
                    totalCount: items.count,
                    storedLimit: storedLimit,
                    loadedPageIndices: loadedPageIndices,
                    pendingPageIndices: pendingPageIndices
               ) {
                loadingSentinel(title: "Loading more")
                    .onAppear {
                        loadPages([nextPage])
                    }
            }
        }
        .onAppear {
            if loadedPageIndices.isEmpty, pendingPageIndices.isEmpty {
                anchorIndex = clampedAnchorIndexHint
            }
            scheduleVisiblePages()
        }
        .onChange(of: items.count) { _, newCount in
            guard newCount > 0 else {
                anchorIndex = 0
                loadedPageIndices = []
                pendingPageIndices = []
                return
            }
            anchorIndex = min(anchorIndex, newCount - 1)
            loadedPageIndices = validPageIndices(loadedPageIndices, totalCount: newCount)
            pendingPageIndices = validPageIndices(pendingPageIndices, totalCount: newCount)
            if renderMode == .slidingWindow {
                loadedPageIndices = SongRenderWindowPolicy.loadedPageIndicesAfterEviction(
                    loadedPageIndices: loadedPageIndices,
                    totalCount: newCount,
                    anchorIndex: anchorIndex,
                    storedLimit: storedLimit
                )
            }
            scheduleVisiblePages()
        }
        .onChange(of: resetToken) { _, _ in
            anchorIndex = clampedAnchorIndexHint
            loadedPageIndices = []
            pendingPageIndices = []
            scheduleVisiblePages()
        }
        .onChange(of: anchorIndexHint) { _, _ in
            anchorIndex = clampedAnchorIndexHint
            loadedPageIndices = []
            pendingPageIndices = []
            scheduleVisiblePages()
        }
        .onChange(of: storedLimit) { _, _ in
            anchorIndex = clampedAnchorIndexHint
            loadedPageIndices = []
            pendingPageIndices = []
            scheduleVisiblePages()
        }
    }

    private var clampedAnchorIndexHint: Int {
        SongRenderWindowPolicy.clampedAnchorIndexHint(anchorIndexHint, totalCount: items.count)
    }

    private func spacerHeight(for hiddenRows: Int) -> CGFloat {
        let sentinelRows = SongRenderWindowPolicy.hiddenSpacerRows(
            hiddenRows: hiddenRows,
            storedLimit: storedLimit
        )
        return max(0, CGFloat(sentinelRows) * (estimatedRowHeight + spacing))
    }

    private func updateAnchorIfNeeded(for index: Int) {
        guard renderMode == .slidingWindow else { return }
        guard let limit = SongRenderWindowPolicy.effectiveLimit(storedLimit), items.count > limit else {
            return
        }

        let threshold = max(4, limit / 5)
        if index <= visibleRange.lowerBound + threshold || index >= visibleRange.upperBound - threshold {
            anchorIndex = index
        }
    }

    @ViewBuilder
    private func loadingPlaceholder(index: Int) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Loading")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: estimatedRowHeight)
        .onAppear {
            loadPage(containing: index)
        }
    }

    @ViewBuilder
    private func loadingSentinel(title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func scheduleVisiblePages() {
        if renderMode == .paged {
            guard SongRenderWindowPolicy.pageSize(forStoredLimit: storedLimit) != nil else { return }
            guard loadedPageIndices.isEmpty, pendingPageIndices.isEmpty else { return }
            loadPages([
                SongRenderWindowPolicy.initialPageIndex(
                    totalCount: items.count,
                    anchorIndex: anchorIndex,
                    storedLimit: storedLimit
                )
            ])
            return
        }

        let pages = SongRenderWindowPolicy.pagesToLoad(
            totalCount: items.count,
            anchorIndex: anchorIndex,
            storedLimit: storedLimit,
            loadedPageIndices: loadedPageIndices.union(pendingPageIndices)
        )
        loadPages(pages)
    }

    private func loadPage(containing index: Int) {
        let pageSize = SongRenderWindowPolicy.pageSize(forStoredLimit: storedLimit) ?? SongRenderWindowPolicy.defaultPageSize
        loadPages([SongRenderWindowPolicy.pageIndex(forRow: index, pageSize: pageSize)])
    }

    private func loadPages(_ pages: [Int]) {
        let pagesToLoad = Set(pages).subtracting(loadedPageIndices).subtracting(pendingPageIndices)
        guard !pagesToLoad.isEmpty else { return }

        pendingPageIndices.formUnion(pagesToLoad)
        Task { @MainActor in
            await Task.yield()
            loadedPageIndices.formUnion(pagesToLoad)
            pendingPageIndices.subtract(pagesToLoad)
            if renderMode == .slidingWindow {
                loadedPageIndices = SongRenderWindowPolicy.loadedPageIndicesAfterEviction(
                    loadedPageIndices: loadedPageIndices,
                    totalCount: items.count,
                    anchorIndex: anchorIndex,
                    storedLimit: storedLimit
                )
            } else {
                loadedPageIndices = validPageIndices(loadedPageIndices, totalCount: items.count)
            }
        }
    }

    private func validPageIndices(_ pageIndices: Set<Int>, totalCount: Int) -> Set<Int> {
        guard let pageSize = SongRenderWindowPolicy.pageSize(forStoredLimit: storedLimit) else {
            return pageIndices
        }
        return pageIndices.filter {
            !SongRenderWindowPolicy.pageRange(pageIndex: $0, totalCount: totalCount, pageSize: pageSize).isEmpty
        }
    }
}
