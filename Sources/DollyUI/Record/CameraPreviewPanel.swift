import AppKit
import SwiftUI

/// The frame around the camera preview: 200 pt wide at 16:9, rounded, on a sheet border.
public struct CameraPreviewFrame<Content: View>: View {
    public static var size: CGSize { CGSize(width: 200, height: 112) }
    let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.inspectorRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.Size.inspectorRadius).strokeBorder(Theme.border.color, lineWidth: 1))
            // Floats over other apps like the bar, so it casts the bar's shadow.
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            .padding(Theme.Size.cardShadowRoom)
            .accessibilityLabel("Camera preview")
    }
}

/// The mirrored camera preview under the Record bar while the Camera switch is on (studio spec,
/// Camera). Click-through and never key; closed before the countdown. The app hands it the live view.
@MainActor
public final class CameraPreviewPanel {
    private var panel: NSPanel?

    public init() {}

    public func show(_ live: NSView, below bar: CGRect) {
        let host = NSHostingView(rootView: CameraPreviewFrame { LiveView(view: live) })
        let size = host.fittingSize
        let panel = self.panel ?? Self.makePanel()
        panel.contentView = host
        panel.setFrame(CGRect(x: bar.midX - size.width / 2, y: bar.minY - size.height + Theme.Size.cardShadowRoom - 8,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    public func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        return panel
    }
}

private struct LiveView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
