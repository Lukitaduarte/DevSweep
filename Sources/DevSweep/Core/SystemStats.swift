import Darwin
import Foundation

enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: tr("pressure.normal")
        case .warning: tr("pressure.warning")
        case .critical: tr("pressure.critical")
        }
    }
}

struct SystemSnapshot: Sendable {
    var memUsed: Int64
    var memTotal: Int64
    var pressure: MemoryPressure
    var diskFree: Int64
    var diskTotal: Int64

    var memFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
    var memoryTight: Bool { pressure != .normal || memFraction > 0.85 }
}

enum SystemStats {
    static func snapshot() -> SystemSnapshot {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var used: Int64 = 0
        if status == KERN_SUCCESS {
            // Same formula as Activity Monitor's "Memory Used": app + wired + compressed.
            let page = Int64(vm_kernel_page_size)
            let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
            used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        }

        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)

        let volume = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])

        return SystemSnapshot(
            memUsed: used,
            memTotal: total,
            pressure: MemoryPressure(rawValue: Int(level)) ?? .normal,
            diskFree: volume?.volumeAvailableCapacityForImportantUsage ?? 0,
            diskTotal: Int64(volume?.volumeTotalCapacity ?? 0)
        )
    }
}
