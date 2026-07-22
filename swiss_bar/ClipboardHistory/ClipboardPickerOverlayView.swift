//
//  ClipboardPickerOverlayView.swift
//  swiss_bar
//

import ImageIO
import SwiftUI

/// Vertical list of clipboard entries, one row per item. Unlike the Window Switcher overlay
/// (keyboard-only, tiles with no obvious click target), rows here are clickable - a list of past
/// clipboard entries is a natural mouse target - so a tap selects and immediately commits.
struct ClipboardPickerOverlayView: View {
    @ObservedObject var viewModel: ClipboardPickerViewModel
    let persistence: ClipboardHistoryPersistence
    let onRowTapped: (Int) -> Void

    private static let rowHeight: CGFloat = 40
    private static let thumbnailMaxPixel: CGFloat = 64

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        row(for: item, index: index)
                            .id(item.id)
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

    private func row(for item: ClipboardItem, index: Int) -> some View {
        HStack(spacing: 10) {
            rowVisual(for: item)
            rowLabel(for: item)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(index == viewModel.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onRowTapped(index) }
        .task(id: item.id) { await loadThumbnailIfNeeded(item) }
    }

    @ViewBuilder
    private func rowVisual(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
        case .image:
            if let thumbnail = viewModel.thumbnails[item.id] {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func rowLabel(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text(let text):
            Text(text.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(1)
                .truncationMode(.tail)
        case .image(_, let pixelSize):
            Text("Image \(Int(pixelSize.width))×\(Int(pixelSize.height))")
                .foregroundStyle(.secondary)
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard viewModel.items.indices.contains(viewModel.selectedIndex) else { return }
        proxy.scrollTo(viewModel.items[viewModel.selectedIndex].id, anchor: .center)
    }

    /// Decodes a small thumbnail via ImageIO rather than a full `NSImage` load - files on disk are
    /// full resolution, and decoding the whole PNG just to draw a ~28pt row icon would waste
    /// memory/time for a picker that can hold hundreds of entries.
    private func loadThumbnailIfNeeded(_ item: ClipboardItem) async {
        guard case .image(let fileName, _) = item.kind, viewModel.thumbnails[item.id] == nil else { return }
        let url = persistence.imageFileURL(fileName: fileName)
        let thumbnail = await Task.detached(priority: .userInitiated) {
            Self.decodeThumbnail(at: url, maxPixelSize: Self.thumbnailMaxPixel)
        }.value
        guard let thumbnail else { return }
        viewModel.thumbnails[item.id] = thumbnail
    }

    nonisolated private static func decodeThumbnail(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
