//
//  SwitcherOverlayView.swift
//  swiss_bar
//

import SwiftUI

struct SwitcherOverlayView: View {
    @ObservedObject var viewModel: SwitcherViewModel

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                VStack(spacing: 6) {
                    Group {
                        if let icon = candidate.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 48, height: 48)
                        } else {
                            Image(systemName: "app")
                                .resizable()
                                .frame(width: 48, height: 48)
                        }
                    }
                    Text(candidate.title)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: 100)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
