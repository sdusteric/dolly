import AppKit
import DollyCore
import Foundation
import ScreenCaptureKit

/// On-screen windows Dolly can record, for the Record bar's menu (spec 4.1). Needs Screen Recording.
public enum WindowCatalog {
    public static func windows() async -> [PickableWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        let screens = await MainActor.run { NSScreen.screens.map { ($0.frame, $0.displayID) } }
        return content.windows.compactMap { window in
            guard window.windowLayer == 0, window.frame.width >= 100, window.frame.height >= 100,
                  let app = window.owningApplication, app.processID != own else { return nil }
            let frame = window.frame.flippedToGlobal
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let display = screens.first { $0.0.contains(center) }?.1 ?? CGMainDisplayID()
            return PickableWindow(id: window.windowID, app: app.applicationName, title: window.title ?? "", frame: frame, displayID: display)
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
}

public extension NSScreen {
    var displayID: UInt32 { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID() }
}
