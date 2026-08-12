import Darwin
import Foundation

/// A snapshot of the BSD process table, via `sysctl` — no subprocess, no parsing of `ps`.
enum ProcessTable {
    struct Entry: Sendable {
        let pid: Int32
        let parentPID: Int32
        /// `p_comm`, so `herdr` rather than the full argv.
        let command: String
        /// Set only for a pid AppKit knows as a running application.
        let bundleID: String?

        /// The pure walk's shape; it deliberately knows nothing about process names.
        var host: HerdrHost.Entry {
            HerdrHost.Entry(pid: pid, parentPID: parentPID, bundleID: bundleID)
        }
    }

    /// `libproc` is tidier but EPERMs on processes we do not own; a terminal's ancestry is root's.
    nonisolated static func entries(bundleIDs: [Int32: String]) -> [Entry] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var byteCount = 0
        guard sysctl(&name, 4, nil, &byteCount, nil, 0) == 0, byteCount > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        // Headroom for processes spawned between sizing and fetching, which would otherwise ENOMEM.
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: byteCount / stride + 32)
        byteCount = processes.count * stride
        guard sysctl(&name, 4, &processes, &byteCount, nil, 0) == 0 else { return [] }

        return processes[0..<(byteCount / stride)].compactMap { process in
            let pid = process.kp_proc.p_pid
            guard pid > 0 else { return nil }
            return Entry(
                pid: pid, parentPID: process.kp_eproc.e_ppid, command: command(of: process),
                bundleID: bundleIDs[pid])
        }
    }

    /// `p_comm` is a fixed-width C buffer, so it is read as one rather than bridged.
    nonisolated private static func command(of process: kinfo_proc) -> String {
        withUnsafePointer(to: process.kp_proc.p_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
        }
    }
}
