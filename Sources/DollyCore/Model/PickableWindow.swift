import CoreGraphics
import Foundation

/// A window the Record bar offers (spec 4.1).
public struct PickableWindow: Identifiable, Hashable, Sendable {
    public var id: UInt32
    public var app: String
    public var title: String
    /// Global points, bottom-left origin.
    public var frame: CGRect
    public var displayID: UInt32
    /// The owning app's process, so the bar can pick the window the owner was looking at.
    public var pid: Int32

    public init(id: UInt32, app: String, title: String, frame: CGRect, displayID: UInt32, pid: Int32 = 0) {
        self.id = id
        self.app = app
        self.title = title
        self.frame = frame
        self.displayID = displayID
        self.pid = pid
    }

    public var label: String { title.isEmpty ? app : "\(app), \(title)" }

    /// Sorts by on-screen order, frontmost first. Windows missing from `order` keep their place after the rest.
    public static func frontToBack(_ windows: [PickableWindow], order: [UInt32]) -> [PickableWindow] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return windows.enumerated()
            .sorted { (rank[$0.element.id] ?? order.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset, $1.offset) }
            .map(\.element)
    }
}
