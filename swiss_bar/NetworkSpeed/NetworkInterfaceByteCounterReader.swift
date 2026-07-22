//
//  NetworkInterfaceByteCounterReader.swift
//  swiss_bar
//

import Darwin
import Foundation

/// A snapshot of one network interface's cumulative byte counters, as reported by `getifaddrs`.
struct InterfaceByteCount {
    let name: String
    let isLoopback: Bool
    let isUp: Bool
    let inBytes: UInt64
    let outBytes: UInt64
}

/// Reads per-interface cumulative traffic counters via `getifaddrs`/`if_data` - there's no
/// notification API for this, so `NetworkSpeedMonitor` polls it on a timer and diffs consecutive
/// reads to get a rate, the same "poll something with no notification API" shape as
/// `ClipboardMonitor`'s pasteboard polling.
enum NetworkInterfaceByteCounterReader {
    static func readAllInterfaces() -> [InterfaceByteCount] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [InterfaceByteCount] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let dataPtr = ifa.ifa_data else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            let flags = Int32(bitPattern: ifa.ifa_flags)
            result.append(InterfaceByteCount(
                name: String(cString: ifa.ifa_name),
                isLoopback: flags & IFF_LOOPBACK != 0,
                isUp: flags & IFF_UP != 0,
                inBytes: UInt64(data.ifi_ibytes),
                outBytes: UInt64(data.ifi_obytes)
            ))
        }
        return result
    }

    /// Sums traffic across active, non-loopback interfaces. VPN/tunnel interfaces are excluded by
    /// name prefix by default so their traffic isn't double-counted on top of the physical
    /// interface it actually rides on.
    nonisolated static func totalBytes(
        from interfaces: [InterfaceByteCount],
        excludingNamePrefixes: Set<String> = ["utun", "ipsec", "ppp"]
    ) -> (inBytes: UInt64, outBytes: UInt64) {
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        for interface in interfaces {
            guard interface.isUp, !interface.isLoopback else { continue }
            guard !excludingNamePrefixes.contains(where: interface.name.hasPrefix) else { continue }
            totalIn += interface.inBytes
            totalOut += interface.outBytes
        }
        return (totalIn, totalOut)
    }
}
