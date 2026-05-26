//
//  PhoneDetailHeader.swift
//  WRhythm
//

import SwiftUI

#if os(iOS)
struct PhoneDetailHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String?

    init(title: String? = nil) {
        self.title = title
    }

    var body: some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(WRhythmTypography.heroTitle)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 52, height: 52)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()
            }

            if let title {
                Text(title)
                    .font(WRhythmTypography.featureTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 68)
            }
        }
        .frame(height: 56)
    }
}
#endif
