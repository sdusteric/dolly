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
