import AVFoundation
import DollyCore
import SwiftUI

/// The stage (spec 6.2). Play mode shows the output (the player, or a still); Aim mode, when a zoom
/// is selected and nothing plays, shows the whole recording at 1x with the zoom's corners.
public struct StageView: View {
    @Bindable var editor: EditorModel
    let image: CGImage?
    let player: AVPlayer?
    let isPlaying: Bool
    let clicks: [Click]
    @FocusState private var focused: Bool

    public static let shapeNote = "16:9, exports 1920 × 1080 for X and Threads"

    public init(editor: EditorModel, image: CGImage?, player: AVPlayer?, isPlaying: Bool, clicks: [Click]) {
        self.editor = editor
        self.image = image
        self.player = player
        self.isPlaying = isPlaying
        self.clicks = clicks
    }

    private var aimZoom: Zoom? { isPlaying ? nil : editor.selectedZoom.flatMap { editor.zoom($0) } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.shapeNote)
                .font(Theme.Font.body)
                .monospacedDigit()
                .foregroundStyle(Theme.muted.color)
                .frame(height: 20)
            GeometryReader { proxy in
                let size = fit(proxy.size)
                ZStack(alignment: .topLeading) {
                    content.frame(width: size.width, height: size.height)
                    if let zoom = aimZoom {
                        AimOverlay(model: AimOverlayModel(take: editor.take, clicks: clicks, stageSize: size), zoom: zoom, editor: editor)
                        Text(AimOverlayModel.hint)
                            .font(Theme.Font.meta)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)))
                            .offset(x: 12, y: size.height - 32)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .coordinateSpace(.named("stage"))
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(phases: .down) { key in handle(key) }
                // The family focus ring: 2 pt ink with a 2 pt gap (spec 10.5).
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink.color, lineWidth: Theme.Size.focusRing)
                    .padding(-4).opacity(focused ? 1 : 0))
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let player, aimZoom == nil {
            PlayerLayerView(player: player)
        } else if let image {
            Image(decorative: image, scale: 1).resizable().interpolation(.high)
        } else {
            Rectangle().fill(Theme.raised.color)
        }
    }

    private func fit(_ space: CGSize) -> CGSize {
        let width = min(space.width, space.height * 16 / 9)
        return CGSize(width: width, height: width * 9 / 16)
    }

    /// Arrows nudge the aim 1 pt (Shift 10), minus and equals change depth by 0.1 (spec 6.2).
    private func handle(_ key: KeyPress) -> KeyPress.Result {
        guard let zoom = aimZoom else { return .ignored }
        let step: Double = key.modifiers.contains(.shift) ? 10 : 1
        switch key.key {
        case .leftArrow: editor.nudgeAim(zoom.id, dx: -step, dy: 0)
        case .rightArrow: editor.nudgeAim(zoom.id, dx: step, dy: 0)
        case .upArrow: editor.nudgeAim(zoom.id, dx: 0, dy: -step)
        case .downArrow: editor.nudgeAim(zoom.id, dx: 0, dy: step)
        case KeyEquivalent("-"): editor.setDepth(zoom.id, zoom.depth - 0.1)
        case KeyEquivalent("="): editor.setDepth(zoom.id, zoom.depth + 0.1)
        default: return .ignored
        }
        return .handled
    }
}
