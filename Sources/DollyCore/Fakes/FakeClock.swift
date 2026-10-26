import Foundation
import Synchronization

public final class FakeClock: DollyClock {
    private let state = Mutex((now: 0.0, sleeps: [Double]()))
    public init(now: Double = 0) { state.withLock { $0.now = now } }
    public func now() -> Double { state.withLock { $0.now } }
    public func set(_ t: Double) { state.withLock { $0.now = t } }
    public var sleeps: [Double] { state.withLock { $0.sleeps } }
    public func sleep(seconds: Double) async {
        state.withLock {
            $0.sleeps.append(seconds)
            $0.now += seconds
        }
    }
}

public final class FakeDiskSpace: DiskSpaceProbing {
    private let value: Mutex<Int64>
    public init(bytes: Int64) { value = Mutex(bytes) }
    public var bytes: Int64 {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
    public func freeBytes(at url: URL) -> Int64? { bytes }
}
