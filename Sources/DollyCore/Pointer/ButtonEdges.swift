import Foundation

public enum ButtonEdge: Sendable, Hashable { case leftDown, leftUp, rightDown, rightUp }

/// Press and release edges between two button bitmasks (bit 0 left, bit 1 right), for the polling
/// click source (spec 4.3, plan B).
public enum ButtonEdges {
    public static func edges(previous: UInt8, current: UInt8) -> [ButtonEdge] {
        var out: [ButtonEdge] = []
        let changed = previous ^ current
        if changed & 1 != 0 { out.append(current & 1 != 0 ? .leftDown : .leftUp) }
        if changed & 2 != 0 { out.append(current & 2 != 0 ? .rightDown : .rightUp) }
        return out
    }
}

/// The event monitor's buttons between two pointer samples. A press that lets go before the next
/// sample still reads as down in that one sample, so a quick trackpad tap is never lost.
public struct ButtonLatch: Sendable, Hashable {
    private var held: UInt8 = 0
    private var pressed: UInt8 = 0

    public init() {}

    public mutating func down(_ mask: UInt8) {
        held |= mask
        pressed |= mask
    }

    public mutating func up(_ mask: UInt8) { held &= ~mask }

    /// The buttons for this sample: those held now and those pressed since the last sample.
    public mutating func sample() -> UInt8 {
        defer { pressed = 0 }
        return held | pressed
    }
}
