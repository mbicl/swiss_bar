//
//  ClipboardHistoryPersistenceTests.swift
//  swiss_barTests
//

import AppKit
import Foundation
import Testing
@testable import swiss_bar

struct ClipboardHistoryPersistenceTests {

    /// Fresh, isolated temp directory per test so tests never touch the real user's Application
    /// Support folder or each other's on-disk state.
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)")
    }

    private func makeTextItem(_ text: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), date: Date(), contentHash: ClipboardContentHasher.hash(text), kind: .text(text))
    }

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image
    }

    @Test func saveAndLoadRoundTripsTextItems() {
        let persistence = ClipboardHistoryPersistence(rootDirectory: makeRoot())
        let items = [makeTextItem("hello"), makeTextItem("world")]
        persistence.save(items)
        #expect(persistence.load() == items)
    }

    @Test func loadOnEmptyDirectoryReturnsEmpty() {
        let persistence = ClipboardHistoryPersistence(rootDirectory: makeRoot())
        #expect(persistence.load().isEmpty)
    }

    @Test func writeImageFileRoundTripsThroughLoadImage() {
        let persistence = ClipboardHistoryPersistence(rootDirectory: makeRoot())
        guard let (fileName, pixelSize, _) = persistence.writeImageFile(makeTestImage()) else {
            Issue.record("writeImageFile failed")
            return
        }
        #expect(pixelSize.width > 0 && pixelSize.height > 0)
        #expect(persistence.loadImage(fileName: fileName) != nil)
    }

    @Test func saveAndLoadRoundTripsImageItems() {
        let persistence = ClipboardHistoryPersistence(rootDirectory: makeRoot())
        guard let (fileName, pixelSize, _) = persistence.writeImageFile(makeTestImage()) else {
            Issue.record("writeImageFile failed")
            return
        }
        let item = ClipboardItem(id: UUID(), date: Date(), contentHash: "hash", kind: .image(fileName: fileName, pixelSize: pixelSize))
        persistence.save([item])
        #expect(persistence.load() == [item])
    }

    @Test func loadSkipsItemWithMissingImageFile() {
        let persistence = ClipboardHistoryPersistence(rootDirectory: makeRoot())
        let missing = ClipboardItem(
            id: UUID(), date: Date(), contentHash: "hash",
            kind: .image(fileName: "missing.png", pixelSize: CGSize(width: 1, height: 1))
        )
        let text = makeTextItem("kept")
        persistence.save([missing, text])
        #expect(persistence.load() == [text])
    }

    @Test func deleteImageFilesRemovesFileFromDisk() {
        let persistence = ClipboardHistoryPersistence(rootDirectory: makeRoot())
        guard let (fileName, pixelSize, _) = persistence.writeImageFile(makeTestImage()) else {
            Issue.record("writeImageFile failed")
            return
        }
        let item = ClipboardItem(id: UUID(), date: Date(), contentHash: "hash", kind: .image(fileName: fileName, pixelSize: pixelSize))
        persistence.deleteImageFiles(for: [item])
        #expect(persistence.loadImage(fileName: fileName) == nil)
    }
}
