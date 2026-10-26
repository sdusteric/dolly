import AppKit
import SwiftUI

/// Drag a rectangle on any screen to choose an area (spec 4.1). One borderless panel per screen;
/// Esc or a click without a drag cancels. Areas under 64 pt a side are refused.
@MainActor
public final class AreaPicker {
    public static let minimumSide: CGFloat = 64
    private var panels: [NSPanel] = []
    private var completion: ((CGRect?, NSScreen?) -> Void)?

    public init() {}

    public func pick(_ completion: @escaping (CGRect?, NSScreen?) -> Void) {
        self.completion = completion
        panels = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = AreaPickerView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.finish = { [weak self] rect in self?.finish(rect.map { panel.convertToScreen($0) }, screen) }
            panel.contentView = view
            panel.makeKeyAndOrderFront(nil)
            return panel
        }
        NSCursor.crosshair.push()
    }

    private func finish(_ rect: CGRect?, _ screen: NSScreen) {
        NSCursor.pop()
        panels.forEach { $0.orderOut(nil) }
        panels = []
        let valid = rect.flatMap { $0.width >= Self.minimumSide && $0.height >= Self.minimumSide ? $0 : nil }
        completion?(valid, valid == nil ? nil : screen)
        completion = nil
    }
}

private final class AreaPickerView: NSView {
    var finish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGRect?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
        guard let current else {
            let hint = "Drag to choose an area. Esc cancels." as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor.white]
            let size = hint.size(withAttributes: attributes)
            hint.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
            return
        }
        NSColor.clear.setFill()
        current.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: current.insetBy(dx: -1, dy: -1))
        path.lineWidth = 1
        path.stroke()
        let label = "\(Int(current.width)) × \(Int(current.height))" as NSString
        label.draw(at: CGPoint(x: current.minX, y: current.minY - 20),
                   withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
    }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = convert(event.locationInWindow, from: nil)
        current = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) { finish?(current) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish?(nil) } else { super.keyDown(with: event) }
    }
}
