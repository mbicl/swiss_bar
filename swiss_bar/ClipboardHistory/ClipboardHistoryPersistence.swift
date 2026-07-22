//
//  ClipboardHistoryPersistence.swift
//  swiss_bar
//

import AppKit
import CryptoKit
import Foundation
import os

/// Disk I/O for clipboard history: a JSON index plus one PNG file per image item. Root directory
/// is injectable so tests never touch the real user's Application Support folder.
struct ClipboardHistoryPersistence {
    private static let logger = Logger(subsystem: "com.MBI.swiss-bar", category: "ClipboardHistoryPersistence")

    let rootDirectory: URL

    /// `~/Library/Application Support/<bundle-id>/ClipboardHistory/` - keyed by bundle ID so the
    /// `swiss_bar_dev` and release targets never share or clobber each other's history.
    static var defaultRootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.MBI.swiss-bar"
        return base.appendingPathComponent(bundleID).appendingPathComponent("ClipboardHistory")
    }

    init(rootDirectory: URL = ClipboardHistoryPersistence.defaultRootDirectory) {
        self.rootDirectory = rootDirectory
    }

    private var indexURL: URL { rootDirectory.appendingPathComponent("index.json") }
    private var imagesDirectory: URL { rootDirectory.appendingPathComponent("Images") }

    /// Drops any item whose referenced image file is missing (e.g. deleted out-of-band, or a
    /// crash left the index and files out of sync) rather than surfacing a broken row.
    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: indexURL),
              let items = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return []
        }
        return items.filter { item in
            switch item.kind {
            case .text:
                return true
            case .image(let fileName, _):
                return FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(fileName).path)
            }
        }
    }

    /// Atomic write: encode fully in memory, write to a temp file, then replace the index in one
    /// filesystem operation so a crash/kill mid-save can never leave a half-written index.
    func save(_ items: [ClipboardItem]) {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            let tmpURL = rootDirectory.appendingPathComponent("index.json.tmp")
            try data.write(to: tmpURL)
            _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: tmpURL)
        } catch {
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteImageFiles(for items: [ClipboardItem]) {
        for item in items {
            if case .image(let fileName, _) = item.kind {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(fileName))
            }
        }
    }

    /// Writes the image to disk at full resolution as PNG. Returns the stored file name, pixel
    /// size (for rendering picker rows without decoding the file), and the encoded bytes (so the
    /// caller can hash them for duplicate suppression without re-reading the file).
    func writeImageFile(_ image: NSImage) -> (fileName: String, pixelSize: CGSize, pngData: Data)? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        let fileName = "\(UUID().uuidString).png"
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try pngData.write(to: imagesDirectory.appendingPathComponent(fileName))
        } catch {
            Self.logger.error("writeImageFile failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let pixelSize = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        return (fileName, pixelSize, pngData)
    }

    func loadImage(fileName: String) -> NSImage? {
        NSImage(contentsOf: imageFileURL(fileName: fileName))
    }

    func imageFileURL(fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }
}

enum ClipboardContentHasher {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ text: String) -> String {
        hash(Data(text.utf8))
    }
}
