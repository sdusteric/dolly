import DollyCore
import DollyRender
import SwiftUI

/// Hit areas over the output on the stage in play mode: the webcam bubble (click selects it, drag
/// moves it anywhere) and the caption at the playhead (click selects it).
struct CameraDragOverlay: View {
    @Bindable var editor: EditorModel
    let stageSize: CGSize
    @State private var dragging = false

    var body: some View {
        let take = editor.take
        let layout = ShapeLayout(shape: take.currentShape, recordingSize: take.size, padding: take.look.padding)
        let s = stageSize.width / max(layout.canvas.width, 1)
        let camera = take.camera.flatMap { $0.isVisible(at: editor.playhead) ? $0 : nil }
        let overlay = OverlayLayout(canvas: layout.canvas, recordingRect: layout.recordingRect, padding: take.look.padding,
                                    camera: camera, captionPosition: take.captions?.position ?? .bottom, captionHeight: 0)
        ZStack(alignment: .topLeading) {
            if let caption = take.captions?.caption(at: editor.playhead),
               let rect = FrameComposer.make(take: take, folder: nil, layout: layout).captionRect(caption.text, camera: camera) {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .frame(width: rect.width * s, height: rect.height * s)
                    .offset(x: rect.minX * s, y: rect.minY * s)
                    .onTapGesture { editor.selectCaption(caption.id) }
                    .accessibilityElement()
                    .accessibilityLabel("Caption: \(caption.text)")
                    .accessibilityAddTraits(.isButton)
            }
            if let bubble = overlay.bubble(at: 0) {
                let r = CGRect(x: bubble.minX * s, y: bubble.minY * s, width: bubble.width * s, height: bubble.height * s)
                Circle().fill(.clear).contentShape(Circle())
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .gesture(drag(stage: stageSize))
                    .accessibilityElement()
                    .accessibilityLabel("Camera")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: stageSize.width, height: stageSize.height, alignment: .topLeading)
    }

    /// Selects on press; moves once the pointer travels, as one undo step.
    private func drag(stage: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("stage"))
            .onChanged { value in
                if !dragging {
                    dragging = true
                    editor.selectCamera()
                    editor.beginGesture()
                }
                guard hypot(value.translation.width, value.translation.height) > 2 else { return }
                let p = CGPoint(x: min(max(value.location.x / stage.width, 0), 1), y: min(max(value.location.y / stage.height, 0), 1))
                editor.setCamera { $0.point = p }
            }
            .onEnded { _ in
                dragging = false
                editor.endGesture()
            }
    }
}
