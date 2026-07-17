//
//  SwitcherMetricsTests.swift
//  swiss_barTests
//

import CoreGraphics
import Testing
@testable import swiss_bar

struct SwitcherMetricsTests {

    private let screen = CGSize(width: 1512, height: 950)

    // MARK: - Horizontal

    @Test func horizontalSizesGrowMonotonically() {
        for content in SwitcherTileContent.allCases {
            let compact = HorizontalSwitcherMetrics.metrics(size: .compact, content: content)
            let medium = HorizontalSwitcherMetrics.metrics(size: .medium, content: content)
            let large = HorizontalSwitcherMetrics.metrics(size: .large, content: content)

            #expect(compact.tileWidth < medium.tileWidth)
            #expect(medium.tileWidth < large.tileWidth)
            #expect(compact.tileHeight < medium.tileHeight)
            #expect(medium.tileHeight < large.tileHeight)
            #expect(compact.iconSize < medium.iconSize)
            #expect(medium.iconSize < large.iconSize)
        }
    }

    @Test func previewTilesAreLargerThanIconTiles() {
        for size in SwitcherSize.allCases {
            let icon = HorizontalSwitcherMetrics.metrics(size: size, content: .appIcon)
            let preview = HorizontalSwitcherMetrics.metrics(size: size, content: .windowPreview)

            #expect(preview.tileWidth > icon.tileWidth)
            #expect(preview.tileHeight > icon.tileHeight)
            #expect(preview.previewSize.width > 0)
            #expect(preview.previewSize.height > 0)
        }
    }

    // MARK: - Vertical

    @Test func verticalSizesGrowMonotonically() {
        let compact = VerticalSwitcherMetrics.metrics(size: .compact)
        let medium = VerticalSwitcherMetrics.metrics(size: .medium)
        let large = VerticalSwitcherMetrics.metrics(size: .large)

        #expect(compact.panelWidth < medium.panelWidth)
        #expect(medium.panelWidth < large.panelWidth)
        #expect(compact.rowHeight < medium.rowHeight)
        #expect(medium.rowHeight < large.rowHeight)
        #expect(compact.iconSize < medium.iconSize)
        #expect(medium.iconSize < large.iconSize)
    }

    // MARK: - Panel sizing

    @Test func horizontalPanelWidthScalesWithCandidateCount() {
        let one = OverlayController.panelSize(style: .horizontal, size: .medium, tileContent: .appIcon, candidateCount: 1, available: screen)
        let five = OverlayController.panelSize(style: .horizontal, size: .medium, tileContent: .appIcon, candidateCount: 5, available: screen)
        #expect(five.width > one.width)
        #expect(five.height == one.height)
    }

    @Test func horizontalPanelNeverExceedsScreenWidth() {
        for size in SwitcherSize.allCases {
            for content in SwitcherTileContent.allCases {
                let panel = OverlayController.panelSize(style: .horizontal, size: size, tileContent: content, candidateCount: 60, available: screen)
                #expect(panel.width <= screen.width)
                #expect(panel.height <= screen.height)
            }
        }
    }

    @Test func horizontalPanelWrapsIntoTallerRowsWhenWidthIsExhausted() {
        let few = OverlayController.panelSize(style: .horizontal, size: .medium, tileContent: .appIcon, candidateCount: 3, available: screen)
        let many = OverlayController.panelSize(style: .horizontal, size: .medium, tileContent: .appIcon, candidateCount: 30, available: screen)
        #expect(many.height > few.height)
    }

    @Test func horizontalPanelUsesFewerColumnsOnNarrowScreens() {
        let narrow = CGSize(width: 800, height: 600)
        let wide = OverlayController.panelSize(style: .horizontal, size: .medium, tileContent: .appIcon, candidateCount: 20, available: screen)
        let cramped = OverlayController.panelSize(style: .horizontal, size: .medium, tileContent: .appIcon, candidateCount: 20, available: narrow)
        #expect(cramped.width < wide.width)
        #expect(cramped.width <= narrow.width)
        #expect(cramped.height >= wide.height)
    }

    @Test func verticalPanelHeightScalesWithCandidateCountUpToCap() {
        let metrics = VerticalSwitcherMetrics.metrics(size: .medium)
        let one = OverlayController.panelSize(style: .vertical, size: .medium, tileContent: .appIcon, candidateCount: 1, available: screen)
        let five = OverlayController.panelSize(style: .vertical, size: .medium, tileContent: .appIcon, candidateCount: 5, available: screen)
        let many = OverlayController.panelSize(style: .vertical, size: .medium, tileContent: .appIcon, candidateCount: 500, available: screen)

        #expect(five.height > one.height)
        #expect(five.width == one.width)
        #expect(many.height <= metrics.maxPanelHeight)
        #expect(many.height <= screen.height * 0.9)
    }
}
