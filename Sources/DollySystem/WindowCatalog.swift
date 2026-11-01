import AppKit
import DollyCore
import Foundation
import ScreenCaptureKit

/// On-screen windows Dolly can record, for the Record bar's menu (spec 4.1), frontmost first.
/// Needs Screen Recording.
public enum WindowCatalog {
    public static func windows() async -> [PickableWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        let screens = await MainActor.run { NSScreen.screens.map { ($0.frame, $0.displayID) } }
        let pickable: [PickableWindow] = content.windows.compactMap { window in
            guard window.windowLayer == 0, window.frame.width >= 100, window.frame.height >= 100,
                  let app = window.owningApplication, app.processID != own else { return nil }
            let frame = window.frame.flippedToGlobal
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let display = screens.first { $0.0.contains(center) }?.1 ?? CGMainDisplayID()
            return PickableWindow(id: window.windowID, app: app.applicationName, title: window.title ?? "",
                                  frame: frame, displayID: display, pid: app.processID)
        }
        return PickableWindow.frontToBack(pickable, order: stackingOrder())
    }

    /// The window in front of the others, skipping Dolly's own, panels and menus (layer above 0) and
    /// windows too small to offer. Needs no permission; read about four times a second while the bar is open.
    public static func frontWindowID() -> UInt32? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return frontWindowID(in: info, excluding: ProcessInfo.processInfo.processIdentifier)
    }

    static func frontWindowID(in info: [[String: Any]], excluding own: Int32) -> UInt32? {
        for window in info {
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != own,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width >= 100, rect.height >= 100,
                  let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            return id
        }
        return nil
    }

    /// Window numbers front to back. CoreGraphics lists on-screen windows in stacking order;
    /// ScreenCaptureKit does not promise one.
    private static func stackingOrder() -> [UInt32] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }
}

public extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID() }
}
