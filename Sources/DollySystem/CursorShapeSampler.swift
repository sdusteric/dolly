import AppKit
import DollyCore
import Foundation
import Synchronization

/// Spike S2: the system pointer's shape at 10 Hz, matched against the standard cursors by hot spot
/// and size. Off unless the owner turns on "Record pointer shapes".
final class CursorShapeSampler: @unchecked Sendable {
    private let shape = Mutex(PointerShape.arrow)
    private var timer: Timer?

    var current: PointerShape { shape.withLock { $0 } }

    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                MainActor.assumeIsolated { self?.read() }
            }
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in self?.timer?.invalidate() }
    }

    @MainActor private func read() {
        guard let cursor = NSCursor.currentSystem else { return }
        func same(_ other: NSCursor) -> Bool { cursor.hotSpot == other.hotSpot && cursor.image.size == other.image.size }
        let value: PointerShape = same(.iBeam) ? .ibeam : same(.pointingHand) ? .pointingHand : same(.arrow) ? .arrow : .other
        shape.withLock { $0 = value }
    }
}
