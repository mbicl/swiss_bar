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

    // MARK: - captureCategories

    @Test func imageDeclaredBeforeTextCapturesAsImage() {
        let types: [NSPasteboard.PasteboardType] = [.tiff, .string]
        #expect(ClipboardMonitor.captureCategories(in: types) == [.image, .text])
    }

    @Test func textDeclaredBeforeImageCapturesAsText() {
        let types: [NSPasteboard.PasteboardType] = [.string, .tiff]
        #expect(ClipboardMonitor.captureCategories(in: types) == [.text, .image])
    }

    @Test func fileURLOnlyYieldsFileURLCategory() {
        let types: [NSPasteboard.PasteboardType] = [.fileURL]
        #expect(ClipboardMonitor.captureCategories(in: types) == [.fileURL])
    }

    @Test func unknownTypesAreIgnored() {
        let types: [NSPasteboard.PasteboardType] = [.html, NSPasteboard.PasteboardType("dyn.something")]
        #expect(ClipboardMonitor.captureCategories(in: types) == [])
    }

    @Test func duplicateCategoryTypesAreDedupedKeepingFirstPosition() {
        let types: [NSPasteboard.PasteboardType] = [.tiff, .png, .string]
        #expect(ClipboardMonitor.captureCategories(in: types) == [.image, .text])
    }

    @Test func emptyTypesYieldsNoCategories() {
        #expect(ClipboardMonitor.captureCategories(in: []) == [])
    }

    // MARK: - isImageFile

    @Test func commonImageExtensionsAreImageFiles() {
        for ext in ["png", "jpg", "jpeg", "heic", "tiff", "gif"] {
            #expect(ClipboardMonitor.isImageFile(URL(fileURLWithPath: "/tmp/photo.\(ext)")), "expected \(ext) to be an image")
        }
    }

    @Test func nonImageExtensionsAreNotImageFiles() {
        for ext in ["txt", "pdf"] {
            #expect(!ClipboardMonitor.isImageFile(URL(fileURLWithPath: "/tmp/doc.\(ext)")), "expected \(ext) to not be an image")
        }
    }

    @Test func unrecognizedExtensionIsNotAnImageFile() {
        #expect(!ClipboardMonitor.isImageFile(URL(fileURLWithPath: "/tmp/file.zzzqux")))
    }

    @Test func extensionlessURLIsNotAnImageFile() {
        #expect(!ClipboardMonitor.isImageFile(URL(fileURLWithPath: "/tmp/noextension")))
    }
}
