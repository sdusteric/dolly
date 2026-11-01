import AppKit
import DollyCore
import Observation
import SwiftUI

/// What the card in the screen corner says about a take that just finished (Snap's Quick Access
/// card, cut down): its poster, name, length and zooms, then Edit or Export.
nonisolated public struct TakeCardModel: Sendable, Equatable {
    /// Seconds before the card closes by itself; hovering holds it open.
    public static let lifetime: Double = 15
    public static let posterWidth: CGFloat = 240
    public static let edgeInset: CGFloat = 16

    public var name: String
    public var duration: Double
    public var zooms: Int
    public var size: CGSize

    public init(name: String, duration: Double, zooms: Int, size: CGSize) {
        self.name = name
        self.duration = duration
        self.zooms = zooms
        self.size = size
    }

    public init(take: Take) {
        self.init(name: take.name, duration: take.duration, zooms: take.zooms.count, size: take.size)
    }

    /// The length is on the poster, so the line under the name counts the zooms.
    public var meta: String {
        switch zooms {
        case 0: "No zooms"
        case 1: "1 zoom"
        default: "\(zooms) zooms"
        }
    }

    /// The take's shape at the card's width, kept between a wide strip and a square.
    public var posterSize: CGSize {
        let width = Self.posterWidth
        guard size.width > 0, size.height > 0 else { return CGSize(width: width, height: width * 9 / 16) }
        return CGSize(width: width, height: min(max(width * size.height / size.width, 96), width))
    }

    /// Bottom-right of the visible frame, like Snap's stack.
    public static func origin(cardSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.maxX - edgeInset - cardSize.width, y: visibleFrame.minY + edgeInset)
    }
}

@Observable
final class TakeCardState {
    var model: TakeCardModel
    var poster: NSImage?
    var shown = false
    @ObservationIgnored var edit: () -> Void = {}
    @ObservationIgnored var export: () -> Void = {}
    @ObservationIgnored var close: () -> Void = {}
    @ObservationIgnored var hover: (Bool) -> Void = { _ in }

    init(model: TakeCardModel, poster: NSImage?) {
        self.model = model
        self.poster = poster
    }
}

/// The corner card after a recording. One at a time: a new take replaces the old card.
@MainActor
public final class TakeCard {
    private var panel: NSPanel?
    private var state: TakeCardState?
    private var closeTask: Task<Void, Never>?

    public init() {}

    public func show(_ model: TakeCardModel, poster: NSImage?, on screen: NSScreen?,
                     edit: @escaping () -> Void, export: @escaping () -> Void) {
        dismiss(animated: false)
        let state = TakeCardState(model: model, poster: poster)
        state.edit = { [weak self] in self?.dismiss(animated: false); edit() }
        state.export = { [weak self] in self?.dismiss(animated: false); export() }
        state.close = { [weak self] in self?.dismiss(animated: true) }
        state.hover = { [weak self] inside in inside ? self?.closeTask?.cancel() : self?.scheduleClose() }
        self.state = state

        let host = FirstMouseHostingView(rootView: TakeCardHost(state: state).focusEffectDisabled())
        let size = host.fittingSize
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let panel = Self.makePanel()
        panel.contentView = host
        // The panel is the card plus its shadow room, so line the card itself up with the inset.
        let room = Theme.Size.cardShadowRoom
        let card = TakeCardModel.origin(cardSize: CGSize(width: size.width - 2 * room, height: size.height - 2 * room), visibleFrame: visible)
        panel.setFrame(CGRect(origin: CGPoint(x: card.x - room, y: card.y - room), size: size), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        state.shown = true
        scheduleClose()
    }

    public func dismiss(animated: Bool) {
        closeTask?.cancel()
        closeTask = nil
        guard let panel else { return }
        self.panel = nil
        state?.shown = false
        state = nil
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return panel.orderOut(nil) }
        Task {
            try? await Task.sleep(for: .seconds(Theme.Motion.cardOut))
            panel.orderOut(nil)
        }
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TakeCardModel.lifetime))
            guard !Task.isCancelled else { return }
            self?.dismiss(animated: true)
        }
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        // Hover holds the card open, and the panel is never key.
        panel.acceptsMouseMovedEvents = true
        return panel
    }
}

/// Takes the first click, so Edit works without a focusing click (Snap's FirstMouseHostingView).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Slides in from the screen edge and leaves the same way (spec 10.6); opacity only with Reduce Motion.
struct TakeCardHost: View {
    let state: TakeCardState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TakeCardView(model: state.model, poster: state.poster.map { Image(nsImage: $0) },
                     edit: state.edit, export: state.export, close: state.close)
            .onHover { state.hover($0) }
            .opacity(state.shown ? 1 : 0)
            .offset(x: state.shown || reduceMotion ? 0 : Theme.Size.cardSlide)
            .animation(state.shown ? .easeOut(duration: Theme.Motion.cardIn) : .easeIn(duration: Theme.Motion.cardOut), value: state.shown)
            // Room for the shadow inside the transparent panel.
            .padding(Theme.Size.cardShadowRoom)
    }
}

public struct TakeCardView: View {
    let model: TakeCardModel
    let poster: Image?
    let edit: () -> Void
    let export: () -> Void
    let close: () -> Void

    public init(model: TakeCardModel, poster: Image?, edit: @escaping () -> Void, export: @escaping () -> Void, close: @escaping () -> Void) {
        self.model = model
        self.poster = poster
        self.edit = edit
        self.export = export
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: edit) {
                ZStack(alignment: .bottomLeading) {
                    posterImage
                    Text(TimeText.short(model.duration))
                        .font(Theme.Font.meta.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(height: 20)
                        .background(Capsule().fill(.black.opacity(0.6)))
                        .padding(6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(model.name) in the editor")

            // Close sits with the title, off the poster, so it never covers what was recorded.
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(Theme.Font.display(14)).lineLimit(1).truncationMode(.tail)
                    Text(model.meta).font(Theme.Font.meta).foregroundStyle(Theme.muted.color)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted.color)
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Close")
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Edit", action: edit).buttonStyle(DollyButtonStyle())
                Button("Export", action: export).buttonStyle(DollyButtonStyle(kind: .primary))
            }
        }
        .foregroundStyle(Theme.ink.color)
        .padding(10)
        .frame(width: TakeCardModel.posterWidth + 20)
        .background(RoundedRectangle(cornerRadius: Theme.Size.inspectorRadius).fill(Theme.sheet.color))
        .overlay(RoundedRectangle(cornerRadius: Theme.Size.inspectorRadius).strokeBorder(Theme.border.color, lineWidth: 1))
        // Floats over other apps, like the Record bar; grouped so only the card casts the shadow.
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    @ViewBuilder private var posterImage: some View {
        let size = model.posterSize
        if let poster {
            poster.resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped()
        } else {
            Rectangle().fill(Theme.raised.color).frame(width: size.width, height: size.height)
        }
    }
}
