import Foundation

/// アプリ全体の CPU の時間とメモリを読む（測るだけ）。
///
/// 2026-11-23 判断（札 #709）: とおまわり号を消すときに、`CamperRenderMeter` から引っ越した。
/// 旅のトランクの計測（`TrunkPerfMeter`）が読む。中身は前と同じ
enum ProcessUsage {

    /// アプリ全体の CPU の時間（ミリ秒・起動からの合計）と、メモリ（phys_footprint・MB）。Linux では無い
    static func current() -> (cpuMs: Double, memMB: Double, internalMB: Double, compressedMB: Double, deviceMB: Double)? {
        #if canImport(Darwin)
        var ts = timespec()
        guard clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) == 0 else { return nil }
        let cpu = Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1_000_000
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let mb = 1_048_576.0
        let mem = kr == KERN_SUCCESS ? Double(info.phys_footprint) / mb : 0
        // 内訳（2026-11-07・#430）: internal=ヒープなど匿名のメモリ  compressed=圧縮  device=デバイス（GPU など）に結んだ分
        let internalMB = kr == KERN_SUCCESS ? Double(info.internal) / mb : 0
        let compressedMB = kr == KERN_SUCCESS ? Double(info.compressed) / mb : 0
        let deviceMB = kr == KERN_SUCCESS ? Double(info.device) / mb : 0
        return (cpu, mem, internalMB, compressedMB, deviceMB)
        #else
        return nil
        #endif
    }

    #if canImport(Darwin)
    /// user_tag 別の常駐の大きさ（`vm_region_recurse_64`）。値は「汚れたページ＋圧縮・退避したページ(MB)/常駐したページ(MB)」。0.3MB 以上だけ、大きい順
    static func vmTagSummary() -> String {
        var address: vm_address_t = 0
        var depth: natural_t = 0
        let page = UInt64(getpagesize())
        var dirty: [UInt32: UInt64] = [:], resident: [UInt32: UInt64] = [:]
        while true {
            var size: vm_size_t = 0
            var info = vm_region_submap_info_data_64_t()
            var count = mach_msg_type_number_t(MemoryLayout<vm_region_submap_info_data_64_t>.size / MemoryLayout<Int32>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: Int32.self, capacity: Int(count)) {
                    vm_region_recurse_64(mach_task_self_, &address, &size, &depth, $0, &count)
                }
            }
            if kr != KERN_SUCCESS { break }
            if info.is_submap != 0 { depth += 1; continue }
            dirty[info.user_tag, default: 0] += UInt64(info.pages_dirtied + info.pages_swapped_out) * page
            resident[info.user_tag, default: 0] += UInt64(info.pages_resident) * page
            address += size
        }
        let mb = 1_048_576.0
        let rows = dirty.keys.map { ($0, Double(dirty[$0]!) / mb, Double(resident[$0] ?? 0) / mb) }
            .filter { $0.1 >= 0.3 || $0.2 >= 0.3 }.sorted { $0.1 > $1.1 }
        let total = String(format: "TOTAL=%.1f/%.1f", Double(dirty.values.reduce(0, +)) / mb, Double(resident.values.reduce(0, +)) / mb)
        return ([total] + rows.map { String(format: "%@=%.1f/%.1f", vmTagName($0.0), $0.1, $0.2) }).joined(separator: " ")
    }

    private static func vmTagName(_ tag: UInt32) -> String {
        let names: [UInt32: String] = [1: "MALLOC", 2: "MALLOC_SMALL", 3: "MALLOC_LARGE", 7: "MALLOC_TINY", 8: "MALLOC_LARGE_REUSABLE",
                                       9: "MALLOC_LARGE_REUSED", 11: "MALLOC_NANO", 12: "MALLOC_MEDIUM", 20: "MACH_MSG", 21: "IOKIT",
                                       30: "STACK", 31: "GUARD", 33: "DYLIB", 42: "COREGRAPHICS", 51: "LAYERKIT", 52: "CGIMAGE",
                                       54: "COREGRAPHICS_DATA", 55: "COREGRAPHICS_SHARED", 56: "COREGRAPHICS_FRAMEBUFFERS",
                                       57: "COREGRAPHICS_BACKINGSTORES", 66: "GLSL", 68: "COREIMAGE", 70: "IMAGEIO", 73: "OS_ALLOC_ONCE",
                                       82: "SWIFT_RUNTIME", 83: "SWIFT_METADATA", 86: "SCENEKIT", 88: "IOSURFACE", 100: "IOACCELERATOR",
                                       103: "COREUI_CACHED_IMAGE_DATA"]
        return names[tag] ?? "tag\(tag)"
    }
    #endif
}
