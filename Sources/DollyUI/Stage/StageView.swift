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
    let aimed: () -> Void
    @State private var showsAimHint: Bool

    public init(editor: EditorModel, image: CGImage?, player: AVPlayer?, isPlaying: Bool, clicks: [Click],
                showsAimHint: Bool = true, aimed: @escaping () -> Void = {}) {
        self.editor = editor
        self.image = image
        self.player = player
        self.isPlaying = isPlaying
        self.clicks = clicks
        self.aimed = aimed
        _showsAimHint = State(initialValue: showsAimHint)
    }

    private var aimZoom: Zoom? { isPlaying ? nil : editor.selectedZoom.flatMap { editor.zoom($0) } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShapeBar(editor: editor)
            GeometryReader { proxy in
                let size = fit(proxy.size)
                ZStack {
                    // A click on the stage around the output clears the selection.
                    RoundedRectangle(cornerRadius: 8).fill(Theme.raised.color)
                        .onTapGesture { editor.select(nil) }
                    ZStack(alignment: .topLeading) {
                        content.frame(width: size.width, height: size.height)
                        if let zoom = aimZoom {
                            AimOverlay(model: AimOverlayModel(take: editor.take, clicks: clicks, stageSize: size), zoom: zoom, editor: editor) {
                                if showsAimHint {
                                    withAnimation(.easeOut(duration: Theme.Motion.saved)) { showsAimHint = false }
                                    aimed()
                                }
                            }
                            if showsAimHint {
                                Text(AimOverlayModel.hint)
                                    .font(Theme.Font.meta)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)))
                                    .offset(x: 12, y: size.height - 32)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        } else if !isPlaying {
                            CameraDragOverlay(editor: editor, stageSize: size)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .coordinateSpace(.named("stage"))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(phases: .down) { key in handle(key) }
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

    /// The output frame at the take's shape, as large as the stage allows.
    private func fit(_ space: CGSize) -> CGSize {
        let canvas = editor.take.currentShape.pixelSize(recording: editor.take.size)
        let aspect = Double(canvas.width) / Double(max(canvas.height, 1))
        let width = min(space.width, space.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    /// Arrows nudge the aim 1 pt (Shift 10), minus and equals change depth by 0.1 (spec 6.2).
    private func handle(_ key: KeyPress) -> KeyPress.Result {
        if key.key == .escape, editor.selection != nil {
            editor.select(nil)
            return .handled
        }
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
