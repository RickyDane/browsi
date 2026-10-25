import Foundation
import IOKit
import SystemConfiguration

/// Hardware facts about the Mac Browsi is running on, for the Profile card.
nonisolated struct MacInfo: Sendable, Equatable {
    /// Marketing name, e.g. "MacBook Pro (14-inch, 2024)"; falls back to a name derived from the identifier.
    var modelName: String
    /// Model identifier, e.g. "Mac16,6".
    var modelIdentifier: String
    /// e.g. "Apple M4 Pro".
    var chip: String
    var memoryBytes: UInt64
    var coreCount: Int
    /// e.g. "26.1".
    var systemVersion: String
    /// e.g. "25B78".
    var systemBuild: String
    var hostName: String

    static let current = MacInfo.read()

    var memory: String { Self.formatMemory(memoryBytes) }
    /// e.g. "macOS 26.1 (25B78)".
    var osVersion: String { "macOS \(systemVersion)" + (systemBuild.isEmpty ? "" : " (\(systemBuild))") }
    /// "Apple M4 Pro" → "M4 Pro".
    var shortChip: String { chip.hasPrefix("Apple ") ? String(chip.dropFirst(6)) : chip }
    var symbol: String { Self.symbol(for: modelName) }

    static func read() -> MacInfo {
        let identifier = sysctlString("hw.model") ?? "Mac"
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Apple silicon"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        return MacInfo(modelName: registryProductName() ?? fallbackName(for: identifier),
                       modelIdentifier: identifier,
                       chip: chip,
                       memoryBytes: ProcessInfo.processInfo.physicalMemory,
                       coreCount: ProcessInfo.processInfo.processorCount,
                       systemVersion: version,
                       systemBuild: sysctlString("kern.osversion") ?? "",
                       hostName: (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ProcessInfo.processInfo.hostName)
    }

    // MARK: Pure helpers

    /// "34359738368" → "32 GB".
    static func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1024 ? String(format: "%.0f TB", gb / 1024) : String(format: "%.0f GB", gb.rounded())
    }

    /// Used when the IORegistry has no product name (Intel Macs, VMs).
    static func fallbackName(for identifier: String) -> String {
        let id = identifier.lowercased()
        for (prefix, name) in [("macbookair", "MacBook Air"), ("macbookpro", "MacBook Pro"), ("macbook", "MacBook"),
                               ("imac", "iMac"), ("macmini", "Mac mini"), ("macpro", "Mac Pro"),
                               ("virtualmac", "Virtual Mac")] where id.hasPrefix(prefix) {
            return name
        }
        return "Mac"
    }

    /// SF Symbol matching the model family.
    static func symbol(for modelName: String) -> String {
        let name = modelName.lowercased()
        if name.contains("macbook") { return "laptopcomputer" }
        if name.contains("imac") { return "desktopcomputer" }
        if name.contains("mac mini") { return "macmini" }
        if name.contains("mac studio") { return "macstudio" }
        if name.contains("mac pro") { return "macpro.gen3" }
        return "macwindow"
    }

    /// `IODeviceTree:/product` → `product-name` (Apple silicon), a NUL-terminated C string.
    static func productName(from data: Data) -> String? {
        let name = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: System access

    private static func registryProductName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return nil }
        return productName(from: value)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }
}
