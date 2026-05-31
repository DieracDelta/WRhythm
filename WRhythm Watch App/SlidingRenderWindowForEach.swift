import SwiftUI

struct SlidingRenderWindowForEach<Element, Row: View>: View {
    private let items: [Element]
    private let estimatedRowHeight: CGFloat
    private let spacing: CGFloat
    private let resetToken: AnyHashable
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
        @ViewBuilder row: @escaping (Int, Element) -> Row
    ) {
        self.items = items
        self.estimatedRowHeight = estimatedRowHeight
        self.spacing = spacing
        self.resetToken = AnyHashable(resetToken)
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
        SongRenderWindowPolicy.renderSlots(
            totalCount: items.count,
            anchorIndex: anchorIndex,
            storedLimit: storedLimit,
            loadedPageIndices: loadedPageIndices
        )
    }

    var body: some View {
        LazyVStack(spacing: spacing) {
            if visibleRange.lowerBound > 0 {
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

            if visibleRange.upperBound < items.count {
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
        }
        .onAppear {
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
            loadedPageIndices = SongRenderWindowPolicy.loadedPageIndicesAfterEviction(
                loadedPageIndices: loadedPageIndices,
                totalCount: newCount,
                anchorIndex: anchorIndex,
                storedLimit: storedLimit
            )
            scheduleVisiblePages()
        }
        .onChange(of: resetToken) { _, _ in
            anchorIndex = 0
            loadedPageIndices = []
            pendingPageIndices = []
            scheduleVisiblePages()
        }
        .onChange(of: storedLimit) { _, _ in
            anchorIndex = min(anchorIndex, max(0, items.count - 1))
            loadedPageIndices = []
            pendingPageIndices = []
            scheduleVisiblePages()
        }
    }

    private func spacerHeight(for hiddenRows: Int) -> CGFloat {
        let sentinelRows = SongRenderWindowPolicy.hiddenSpacerRows(
            hiddenRows: hiddenRows,
            storedLimit: storedLimit
        )
        return max(0, CGFloat(sentinelRows) * (estimatedRowHeight + spacing))
    }

    private func updateAnchorIfNeeded(for index: Int) {
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
        let pages = SongRenderWindowPolicy.pagesToLoad(
            totalCount: items.count,
            anchorIndex: anchorIndex,
            storedLimit: storedLimit,
            loadedPageIndices: loadedPageIndices.union(pendingPageIndices)
        )
        loadPages(pages)
    }

    private func loadPage(containing index: Int) {
        loadPages([SongRenderWindowPolicy.pageIndex(forRow: index, pageSize: SongRenderWindowPolicy.defaultPageSize)])
    }

    private func loadPages(_ pages: [Int]) {
        let pagesToLoad = Set(pages).subtracting(loadedPageIndices).subtracting(pendingPageIndices)
        guard !pagesToLoad.isEmpty else { return }

        pendingPageIndices.formUnion(pagesToLoad)
        Task { @MainActor in
            await Task.yield()
            loadedPageIndices.formUnion(pagesToLoad)
            pendingPageIndices.subtract(pagesToLoad)
            loadedPageIndices = SongRenderWindowPolicy.loadedPageIndicesAfterEviction(
                loadedPageIndices: loadedPageIndices,
                totalCount: items.count,
                anchorIndex: anchorIndex,
                storedLimit: storedLimit
            )
        }
    }
}
