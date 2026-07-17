//
//  SwitcherStyle.swift
//  swiss_bar
//

import SwiftUI

/// Visual layout of the switcher HUD, user-selectable in Settings.
enum SwitcherStyle: String, CaseIterable {
    /// The original layout: a horizontal row of large app-icon tiles.
    case horizontal
    /// A compact vertical list with small icons and room for long window titles.
    case vertical

    static let defaultsKey = "switcherStyle"

    static var current: SwitcherStyle {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SwitcherStyle.init) ?? .horizontal
    }
}

/// Overall scale of the switcher HUD, user-selectable in Settings.
enum SwitcherSize: String, CaseIterable {
    case compact
    case medium
    case large

    static let defaultsKey = "switcherSize"

    static var current: SwitcherSize {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SwitcherSize.init) ?? .medium
    }
}

/// What each tile shows in the horizontal style: the app's icon, or a live thumbnail of the
/// window itself (requires Screen Recording permission - falls back to the icon per-tile when a
/// capture isn't available). The vertical list always uses small icons.
enum SwitcherTileContent: String, CaseIterable {
    case appIcon
    case windowPreview

    static let defaultsKey = "switcherTileContent"

    static var current: SwitcherTileContent {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(SwitcherTileContent.init) ?? .appIcon
    }
}

/// Layout constants for the horizontal style, derived from size + tile content.
struct HorizontalSwitcherMetrics {
    let tileWidth: CGFloat
    /// Height of one row of tiles (the grid wraps into multiple rows when tiles don't fit the screen).
    let tileHeight: CGFloat
    let iconSize: CGFloat
    let previewSize: CGSize
    let titleMaxWidth: CGFloat
    let titleFont: Font

    /// Size of the app-icon badge overlaid on a window preview.
    var badgeSize: CGFloat { max(18, previewSize.height * 0.3) }

    nonisolated static func metrics(size: SwitcherSize, content: SwitcherTileContent) -> HorizontalSwitcherMetrics {
        switch (size, content) {
        case (.compact, .appIcon):
            return .init(tileWidth: 88, tileHeight: 64, iconSize: 32, previewSize: .zero, titleMaxWidth: 76, titleFont: .caption2)
        case (.medium, .appIcon):
            return .init(tileWidth: 116, tileHeight: 100, iconSize: 48, previewSize: .zero, titleMaxWidth: 100, titleFont: .caption)
        case (.large, .appIcon):
            return .init(tileWidth: 152, tileHeight: 136, iconSize: 64, previewSize: .zero, titleMaxWidth: 132, titleFont: .callout)
        case (.compact, .windowPreview):
            return .init(tileWidth: 136, tileHeight: 110, iconSize: 32, previewSize: CGSize(width: 112, height: 70), titleMaxWidth: 112, titleFont: .caption2)
        case (.medium, .windowPreview):
            return .init(tileWidth: 184, tileHeight: 146, iconSize: 48, previewSize: CGSize(width: 160, height: 100), titleMaxWidth: 160, titleFont: .caption)
        case (.large, .windowPreview):
            return .init(tileWidth: 232, tileHeight: 182, iconSize: 64, previewSize: CGSize(width: 208, height: 130), titleMaxWidth: 208, titleFont: .callout)
        }
    }
}

/// Layout constants for the vertical style, derived from size.
struct VerticalSwitcherMetrics {
    let panelWidth: CGFloat
    let maxPanelHeight: CGFloat
    let rowHeight: CGFloat
    let iconSize: CGFloat
    let titleFont: Font

    nonisolated static func metrics(size: SwitcherSize) -> VerticalSwitcherMetrics {
        switch size {
        case .compact:
            return .init(panelWidth: 400, maxPanelHeight: 480, rowHeight: 30, iconSize: 16, titleFont: .callout)
        case .medium:
            return .init(panelWidth: 480, maxPanelHeight: 600, rowHeight: 38, iconSize: 22, titleFont: .body)
        case .large:
            return .init(panelWidth: 560, maxPanelHeight: 700, rowHeight: 48, iconSize: 28, titleFont: .title3)
        }
    }
}
