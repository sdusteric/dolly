import DollyCore
import Foundation

/// Free space on the volume holding the takes (spec 4.2), from the important-usage capacity.
public final class LiveDiskSpace: DiskSpaceProbing {
    public init() {}

    public func freeBytes(at url: URL) -> Int64? {
        var current = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.pathComponents.count > 1 {
            current = current.deletingLastPathComponent()
        }
        do {
            let values = try current.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
            return values.volumeAvailableCapacity.map(Int64.init)
        } catch {
            return nil
        }
    }
}

/// The host clock ScreenCaptureKit stamps frames with, and real sleeps.
public final class HostClock: DollyClock {
    public init() {}
    public func now() -> Double { PointerSampler.hostNow() }
    public func sleep(seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
}
