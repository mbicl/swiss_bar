//
//  ClipboardMonitorTests.swift
//  swiss_barTests
//

import AppKit
import Testing
@testable import swiss_bar

struct ClipboardMonitorTests {

    @Test func concealedTypePresentIsDetected() {
        let types: [NSPasteboard.PasteboardType] = [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")]
        #expect(ClipboardMonitor.containsConcealedType(types) == true)
    }

    @Test func concealedTypeAbsentIsNotDetected() {
        let types: [NSPasteboard.PasteboardType] = [.string, .tiff]
        #expect(ClipboardMonitor.containsConcealedType(types) == false)
    }

    @Test func emptyTypesIsNotConcealed() {
        #expect(ClipboardMonitor.containsConcealedType([]) == false)
    }

    @Test func matchingHashIsDuplicateOfTop() {
        #expect(ClipboardMonitor.isDuplicateOfTop(hash: "abc", topHash: "abc") == true)
    }

    @Test func differingHashIsNotDuplicateOfTop() {
        #expect(ClipboardMonitor.isDuplicateOfTop(hash: "abc", topHash: "def") == false)
    }

    @Test func hashAgainstEmptyHistoryIsNotDuplicate() {
        #expect(ClipboardMonitor.isDuplicateOfTop(hash: "abc", topHash: nil) == false)
    }
}
