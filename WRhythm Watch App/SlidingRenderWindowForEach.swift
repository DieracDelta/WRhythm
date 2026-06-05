import SwiftUI

struct SlidingRenderWindowForEach<Element, Row: View>: View {
    private let items: [Element]
    private let estimatedRowHeight: CGFloat
    private let spacing: CGFloat
    private let resetToken: AnyHashable
    private let anchorIndexHint: Int
    private let renderMode: SongRenderWindowPolicy.RenderMode
    private let showsAnchorPageJump: Bool
    private let anchorPageJumpTitle: String
    private let row: (Int, Element) -> Row

    @AppStorage(SongRenderWindowPolicy.userDefaultsKey) private var storedLimit = SongRenderWindowPolicy.defaultLimit
    @State private var anchorIndex = 0
    @State private var displayedPageIndex = 0
    @State private var loadedPageIndices: Set<Int> = []
    @State private var pendingPageIndices: Set<Int> = []

    init(
        _ items: [Element],
        estimatedRowHeight: CGFloat = 64,
        spacing: CGFloat = 0,
        resetToken: some Hashable = 0,
        anchorIndexHint: Int = 0,
        renderMode: SongRenderWindowPolicy.RenderMode = .paged,
        showsAnchorPageJump: Bool = false,
        anchorPageJumpTitle: String = "Current song",
        @ViewBuilder row: @escaping (Int, Element) -> Row
    ) {
        self.items = items
        self.estimatedRowHeight = estimatedRowHeight
        self.spacing = spacing
        self.resetToken = AnyHashable(resetToken)
        self.anchorIndexHint = anchorIndexHint
        self.renderMode = renderMode
        self.showsAnchorPageJump = showsAnchorPageJump
        self.anchorPageJumpTitle = anchorPageJumpTitle
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
                displayedPageIndex: displayedPageIndex,
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
                    displayedPageIndex: displayedPageIndex
               ) {
                Button(action: {
                    showPagedWindow(previousPage)
                }) {
                    pageNavigationControl(title: "Previous page", systemImage: "chevron.up.circle.fill")
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

            if showsAnchorPageJump,
               renderMode == .paged,
               let currentPage = SongRenderWindowPolicy.currentAnchorPageIndexToLoad(
                    totalCount: items.count,
                    anchorIndex: clampedAnchorIndexHint,
                    storedLimit: storedLimit,
                    displayedPageIndex: displayedPageIndex
               ) {
                Button(action: {
                    showPagedWindow(currentPage)
                }) {
                    pageNavigationControl(title: anchorPageJumpTitle, systemImage: "scope")
                }
                .buttonStyle(.plain)
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
                    displayedPageIndex: displayedPageIndex
               ) {
                Button(action: {
                    showPagedWindow(nextPage)
                }) {
                    pageNavigationControl(title: "Next page", systemImage: "chevron.down.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            if loadedPageIndices.isEmpty, pendingPageIndices.isEmpty {
                anchorIndex = clampedAnchorIndexHint
                displayedPageIndex = initialPagedPageIndex
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
            if renderMode == .paged {
                displayedPageIndex = clampedPageIndex(displayedPageIndex, totalCount: newCount)
                if !loadedPageIndices.contains(displayedPageIndex),
                   !pendingPageIndices.contains(displayedPageIndex) {
                    showPagedWindow(displayedPageIndex)
                }
                return
            }
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
            resetPagedWindowOrScheduleVisiblePages()
        }
        .onChange(of: anchorIndexHint) { _, _ in
            if !SongRenderWindowPolicy.shouldResetWindowWhenAnchorChanges(renderMode: renderMode) {
                anchorIndex = clampedAnchorIndexHint
                return
            }
            resetPagedWindowOrScheduleVisiblePages()
        }
        .onChange(of: storedLimit) { _, _ in
            resetPagedWindowOrScheduleVisiblePages()
        }
    }

    private var clampedAnchorIndexHint: Int {
        SongRenderWindowPolicy.clampedAnchorIndexHint(anchorIndexHint, totalCount: items.count)
    }

    private var initialPagedPageIndex: Int {
        SongRenderWindowPolicy.initialPageIndex(
            totalCount: items.count,
            anchorIndex: clampedAnchorIndexHint,
            storedLimit: storedLimit
        )
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
            if renderMode == .slidingWindow {
                loadPage(containing: index)
            }
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

    @ViewBuilder
    private func pageNavigationControl(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(WRhythmTheme.accent)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(WRhythmTheme.accent.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(WRhythmTheme.accent.opacity(0.35), lineWidth: 1)
        }
        .contentShape(Capsule())
        .accessibilityLabel(title)
    }

    private func scheduleVisiblePages() {
        if renderMode == .paged {
            guard SongRenderWindowPolicy.pageSize(forStoredLimit: storedLimit) != nil else { return }
            guard loadedPageIndices.isEmpty, pendingPageIndices.isEmpty else { return }
            showPagedWindow(displayedPageIndex)
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

    private func resetPagedWindowOrScheduleVisiblePages() {
        anchorIndex = clampedAnchorIndexHint
        loadedPageIndices = []
        pendingPageIndices = []

        guard renderMode == .paged else {
            scheduleVisiblePages()
            return
        }

        displayedPageIndex = initialPagedPageIndex
        showPagedWindow(displayedPageIndex)
    }

    private func showPagedWindow(_ pageIndex: Int) {
        guard renderMode == .paged else {
            loadPages([pageIndex])
            return
        }

        guard SongRenderWindowPolicy.pageSize(forStoredLimit: storedLimit) != nil else {
            loadedPageIndices = [0]
            pendingPageIndices = []
            return
        }

        let validPage = clampedPageIndex(pageIndex, totalCount: items.count)
        guard !SongRenderWindowPolicy.pageRange(
            pageIndex: validPage,
            totalCount: items.count,
            pageSize: SongRenderWindowPolicy.pageSize(forStoredLimit: storedLimit) ?? SongRenderWindowPolicy.defaultPageSize
        ).isEmpty else {
            loadedPageIndices = []
            pendingPageIndices = []
            return
        }

        displayedPageIndex = validPage
        loadedPageIndices = []
        pendingPageIndices = [validPage]

        Task { @MainActor in
            await Task.yield()
            guard displayedPageIndex == validPage else { return }
            loadedPageIndices = [validPage]
            pendingPageIndices = []
        }
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

    private func clampedPageIndex(_ pageIndex: Int, totalCount: Int) -> Int {
        guard totalCount > 0,
              let pageSize = SongRenderWindowPolicy.pageSize(forStoredLimit: storedLimit) else {
            return 0
        }
        let maxPage = SongRenderWindowPolicy.pageIndex(forRow: totalCount - 1, pageSize: pageSize)
        return min(max(pageIndex, 0), maxPage)
    }
}
