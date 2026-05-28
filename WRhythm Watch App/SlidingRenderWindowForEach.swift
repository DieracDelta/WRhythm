import SwiftUI

struct SlidingRenderWindowForEach<Element, Row: View>: View {
    private let items: [Element]
    private let estimatedRowHeight: CGFloat
    private let spacing: CGFloat
    private let resetToken: AnyHashable
    private let row: (Int, Element) -> Row

    @AppStorage(SongRenderWindowPolicy.userDefaultsKey) private var storedLimit = SongRenderWindowPolicy.defaultLimit
    @State private var anchorIndex = 0

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

    var body: some View {
        LazyVStack(spacing: spacing) {
            if visibleRange.lowerBound > 0 {
                Color.clear
                    .frame(height: spacerHeight(for: visibleRange.lowerBound))
                    .onAppear {
                        anchorIndex = max(0, visibleRange.lowerBound - 1)
                    }
            }

            ForEach(Array(visibleRange), id: \.self) { index in
                row(index, items[index])
                    .onAppear {
                        updateAnchorIfNeeded(for: index)
                    }
            }

            if visibleRange.upperBound < items.count {
                Color.clear
                    .frame(height: spacerHeight(for: items.count - visibleRange.upperBound))
                    .onAppear {
                        anchorIndex = min(items.count - 1, visibleRange.upperBound)
                    }
            }
        }
        .onChange(of: items.count) { _, newCount in
            guard newCount > 0 else {
                anchorIndex = 0
                return
            }
            anchorIndex = min(anchorIndex, newCount - 1)
        }
        .onChange(of: resetToken) { _, _ in
            anchorIndex = 0
        }
    }

    private func spacerHeight(for hiddenRows: Int) -> CGFloat {
        max(0, CGFloat(hiddenRows) * (estimatedRowHeight + spacing))
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
}
