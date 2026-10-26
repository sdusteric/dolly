import CoreGraphics
import Foundation

/// A click that counts (spec 4.5). `t` is seconds from the recording's first frame.
public struct Click: Hashable, Sendable {
    public var id: Int
    public var t: Double
    public var point: CGPoint
    public var isDrag: Bool
    public var dragEnd: Double?

    public init(id: Int, t: Double, point: CGPoint, isDrag: Bool = false, dragEnd: Double? = nil) {
        self.id = id
        self.t = t
        self.point = point
        self.isDrag = isDrag
        self.dragEnd = dragEnd
    }
}

/// Turns the pointer log's left button edges into clicks (spec 4.5): a double-click is one click,
/// a long or moving press is a drag, and Dolly's own countdown and stop clicks never count.
public enum ClickDetector {
    public static let doubleClickInterval = 0.35
    public static let doubleClickDistance = 6.0
    public static let dragHold = 0.4
    public static let dragDistance = 8.0
    public static let stopGuard = 0.5

    public static func clicks(
        from samples: [PointerSample], geometry: RecordingGeometry, recordingStartHost: Double, stopRequestHost: Double?
    ) -> [Click] {
        struct Press { var down: Double; var up: Double?; var at: CGPoint; var moved: Double }
        var presses: [Press] = []
        var current: Press?
        var wasDown = false
        for s in samples.sorted(by: { $0.t < $1.t }) {
            let p = CGPoint(x: Double(s.x), y: Double(s.y))
            if s.leftDown && !wasDown {
                current = Press(down: s.t, up: nil, at: p, moved: 0)
            } else if s.leftDown, var press = current {
                press.moved = max(press.moved, hypot(p.x - press.at.x, p.y - press.at.y))
                current = press
            } else if !s.leftDown && wasDown, var press = current {
                press.up = s.t
                presses.append(press)
                current = nil
            }
            wasDown = s.leftDown
        }
        if let press = current { presses.append(press) }

        var out: [Click] = []
        var lastKept: (down: Double, at: CGPoint)?
        for press in presses {
            guard press.down >= recordingStartHost else { continue }
            if let stop = stopRequestHost, press.down >= stop - stopGuard { continue }
            guard let point = geometry.toRecording(press.at, at: press.down) else { continue }
            if let last = lastKept, press.down - last.down <= doubleClickInterval,
               hypot(press.at.x - last.at.x, press.at.y - last.at.y) <= doubleClickDistance {
                continue
            }
            lastKept = (press.down, press.at)
            let held = (press.up ?? press.down) - press.down
            let isDrag = held > dragHold || press.moved > dragDistance
            out.append(Click(
                id: out.count, t: press.down - recordingStartHost, point: point, isDrag: isDrag,
                dragEnd: isDrag ? press.up.map { $0 - recordingStartHost } : nil
            ))
        }
        return out
    }
}
