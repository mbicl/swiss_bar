//
//  NetworkInterfaceByteCounterReaderTests.swift
//  swiss_barTests
//

import Testing
@testable import swiss_bar

struct NetworkInterfaceByteCounterReaderTests {
    @Test func sumsOnlyUpNonLoopbackInterfaces() {
        let interfaces = [
            InterfaceByteCount(name: "en0", isLoopback: false, isUp: true, inBytes: 100, outBytes: 50),
            InterfaceByteCount(name: "lo0", isLoopback: true, isUp: true, inBytes: 999, outBytes: 999),
            InterfaceByteCount(name: "en1", isLoopback: false, isUp: false, inBytes: 500, outBytes: 500),
        ]
        let totals = NetworkInterfaceByteCounterReader.totalBytes(from: interfaces)
        #expect(totals.inBytes == 100)
        #expect(totals.outBytes == 50)
    }

    @Test func excludesVPNTunnelPrefixes() {
        let interfaces = [
            InterfaceByteCount(name: "en0", isLoopback: false, isUp: true, inBytes: 100, outBytes: 50),
            InterfaceByteCount(name: "utun3", isLoopback: false, isUp: true, inBytes: 200, outBytes: 200),
            InterfaceByteCount(name: "ipsec0", isLoopback: false, isUp: true, inBytes: 300, outBytes: 300),
        ]
        let totals = NetworkInterfaceByteCounterReader.totalBytes(from: interfaces)
        #expect(totals.inBytes == 100)
        #expect(totals.outBytes == 50)
    }

    @Test func emptyInterfacesReturnsZero() {
        let totals = NetworkInterfaceByteCounterReader.totalBytes(from: [])
        #expect(totals.inBytes == 0)
        #expect(totals.outBytes == 0)
    }

    @Test func sumsAcrossMultipleActiveInterfaces() {
        let interfaces = [
            InterfaceByteCount(name: "en0", isLoopback: false, isUp: true, inBytes: 100, outBytes: 50),
            InterfaceByteCount(name: "en1", isLoopback: false, isUp: true, inBytes: 40, outBytes: 10),
        ]
        let totals = NetworkInterfaceByteCounterReader.totalBytes(from: interfaces)
        #expect(totals.inBytes == 140)
        #expect(totals.outBytes == 60)
    }
}
