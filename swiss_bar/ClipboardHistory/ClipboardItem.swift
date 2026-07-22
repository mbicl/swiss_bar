//
//  ClipboardItem.swift
//  swiss_bar
//

import CoreGraphics
import Foundation

/// One recorded clipboard entry. Text is stored inline (cheap, keeps the on-disk index simple);
/// image bytes live on disk as a separate file, referenced by name, since inlining full-resolution
/// PNGs into a JSON index that's rewritten on every capture would make every save expensive.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    /// SHA-256 of the captured content (UTF-8 text bytes, or PNG bytes for images) - lets
    /// `ClipboardMonitor` recognize "this is the same thing already at the top of history" without
    /// re-decoding/re-comparing full content on every poll tick.
    let contentHash: String
    let kind: Kind

    enum Kind: Equatable {
        case text(String)
        case image(fileName: String, pixelSize: CGSize)
    }
}

extension ClipboardItem.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, fileName, width, height
    }

    private enum Discriminator: String, Codable {
        case text, image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Discriminator.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            let fileName = try container.decode(String.self, forKey: .fileName)
            let width = try container.decode(CGFloat.self, forKey: .width)
            let height = try container.decode(CGFloat.self, forKey: .height)
            self = .image(fileName: fileName, pixelSize: CGSize(width: width, height: height))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(Discriminator.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let fileName, let pixelSize):
            try container.encode(Discriminator.image, forKey: .type)
            try container.encode(fileName, forKey: .fileName)
            try container.encode(pixelSize.width, forKey: .width)
            try container.encode(pixelSize.height, forKey: .height)
        }
    }
}
