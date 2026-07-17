//
//  SwitcherOverlayView.swift
//  swiss_bar
//

import SwiftUI

struct SwitcherOverlayView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    let style: SwitcherStyle
    let size: SwitcherSize
    let tileContent: SwitcherTileContent

    var body: some View {
        switch style {
        case .horizontal:
            HorizontalSwitcherView(
                viewModel: viewModel,
                tileContent: tileContent,
                metrics: .metrics(size: size, content: tileContent)
            )
        case .vertical:
            VerticalSwitcherView(viewModel: viewModel, metrics: .metrics(size: size))
        }
    }
}

/// The original layout: a grid of tiles (wrapping into multiple rows when they don't fit the
/// screen width), each showing either the app icon or a live window thumbnail (with an app-icon
/// badge) depending on the tile-content setting.
struct HorizontalSwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    let tileContent: SwitcherTileContent
    let metrics: HorizontalSwitcherMetrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: metrics.tileWidth, maximum: metrics.tileWidth), spacing: 16)],
                    spacing: 12
                ) {
                    ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                        VStack(spacing: 6) {
                            tileVisual(for: candidate)
                            Text(candidate.title)
                                .font(metrics.titleFont)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: metrics.titleMaxWidth)
                        }
                        .frame(width: metrics.tileWidth, height: metrics.tileHeight)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                        )
                        .id(candidate.id)
                    }
                }
                .padding(20)
            }
            .onChange(of: viewModel.selectedIndex) {
                scrollToSelection(proxy)
            }
            .onAppear {
                scrollToSelection(proxy)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard viewModel.candidates.indices.contains(viewModel.selectedIndex) else { return }
        proxy.scrollTo(viewModel.candidates[viewModel.selectedIndex].id, anchor: .center)
    }

    @ViewBuilder
    private func tileVisual(for candidate: CandidateWindow) -> some View {
        if tileContent == .windowPreview,
           let windowID = candidate.windowID,
           let preview = viewModel.previews[windowID] {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: metrics.previewSize.width, maxHeight: metrics.previewSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                AppIconView(icon: candidate.appIcon, size: metrics.badgeSize)
                    .offset(x: 5, y: 5)
            }
            .frame(width: metrics.previewSize.width, height: metrics.previewSize.height)
        } else if tileContent == .windowPreview {
            // Preview mode but no capture available for this window - icon centered in the same
            // footprint so the row of tiles stays aligned.
            AppIconView(icon: candidate.appIcon, size: metrics.iconSize)
                .frame(width: metrics.previewSize.width, height: metrics.previewSize.height)
        } else {
            AppIconView(icon: candidate.appIcon, size: metrics.iconSize)
        }
    }
}

/// Compact vertical list: small icon, wide window title (middle-truncated), app name trailing.
/// Scrolls the selection into view so long lists stay navigable.
struct VerticalSwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    let metrics: VerticalSwitcherMetrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.candidates.enumerated()), id: \.element.id) { index, candidate in
                        HStack(spacing: 10) {
                            AppIconView(icon: candidate.appIcon, size: metrics.iconSize)
                            Text(candidate.title)
                                .font(metrics.titleFont)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(candidate.appName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: metrics.rowHeight, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                        )
                        .id(candidate.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: viewModel.selectedIndex) {
                scrollToSelection(proxy)
            }
            .onAppear {
                scrollToSelection(proxy)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard viewModel.candidates.indices.contains(viewModel.selectedIndex) else { return }
        proxy.scrollTo(viewModel.candidates[viewModel.selectedIndex].id, anchor: .center)
    }
}

private struct AppIconView: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .resizable()
                .frame(width: size, height: size)
        }
    }
}
