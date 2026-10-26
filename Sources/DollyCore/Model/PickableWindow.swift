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

    public init(id: UInt32, app: String, title: String, frame: CGRect, displayID: UInt32) {
        self.id = id
        self.app = app
        self.title = title
        self.frame = frame
        self.displayID = displayID
    }

    public var label: String { title.isEmpty ? app : "\(app), \(title)" }
}
