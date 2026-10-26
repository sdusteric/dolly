import AppKit
import DollyCore
import SwiftUI

/// Aim mode (spec 6.2): a scrim outside the selected zoom's view, four spike-tape corners, the tape
/// label, a ring at the click. Drag inside to re-aim, drag a corner to change depth. Drags follow the
/// pointer 1:1 with no easing (spec 10.6) and each drag is one undo step.
struct AimOverlay: View {
    let model: AimOverlayModel
    let zoom: Zoom
    let editor: EditorModel
    @State private var start: Zoom?

    static let leg: CGFloat = 26
    static let tape: CGFloat = 5

    var body: some View {
        let view = model.viewRect(for: zoom)
        ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: model.stageSize))
                p.addRect(view)
            }
            .fill(Theme.scrim.color, style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle().fill(Color.white.opacity(0.001))
                .frame(width: view.width, height: view.height)
                .offset(x: view.minX, y: view.minY)
                .pointerStyle(.grabIdle)
                .gesture(moveGesture)

            ForEach(AimOverlayModel.Corner.allCases, id: \.self) { corner in
                cornerMark(corner, view: view)
            }

            if let click = model.clickPoint(for: zoom) {
                let p = model.stagePoint(click)
                Circle().strokeBorder(.white, lineWidth: 2)
                    .background(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 3))
                    .frame(width: 16, height: 16)
                    .offset(x: p.x - 8, y: p.y - 8)
                    .allowsHitTesting(false)
            }

            Text(model.label(for: zoom))
                .font(Theme.Font.display(13))
                .foregroundStyle(Theme.onTape.color)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Theme.tape.color)
                .offset(x: view.minX, y: view.minY >= 34 ? view.minY - 30 : view.minY + 8)
                .allowsHitTesting(false)
        }
        .frame(width: model.stageSize.width, height: model.stageSize.height, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.label(for: zoom))
    }

    private func cornerMark(_ corner: AimOverlayModel.Corner, view: CGRect) -> some View {
        let x = corner == .topLeft || corner == .bottomLeft ? view.minX : view.maxX
        let y = corner == .topLeft || corner == .topRight ? view.minY : view.maxY
        let sx: CGFloat = corner == .topLeft || corner == .bottomLeft ? 1 : -1
        let sy: CGFloat = corner == .topLeft || corner == .topRight ? 1 : -1
        let shape = Path { p in
            p.move(to: CGPoint(x: 0, y: Self.leg * sy))
            p.addLine(to: .zero)
            p.addLine(to: CGPoint(x: Self.leg * sx, y: 0))
        }
        return ZStack {
            shape.stroke(Theme.ink.color.opacity(0.6), style: StrokeStyle(lineWidth: Self.tape + 2, lineCap: .square))
            shape.stroke(Theme.tape.color, style: StrokeStyle(lineWidth: Self.tape, lineCap: .square))
        }
        .frame(width: 1, height: 1)
        .offset(x: x, y: y)
        .background(alignment: .topLeading) {
            Color.white.opacity(0.001).frame(width: 30, height: 30).offset(x: x - 15, y: y - 15)
                .pointerStyle(.frameResize(position: Self.position(corner)))
                .gesture(cornerGesture(corner))
        }
    }

    private static func position(_ corner: AimOverlayModel.Corner) -> FrameResizePosition {
        switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("stage"))
            .onChanged { value in
                let from = begin()
                let snaps = !NSEvent.modifierFlags.contains(.shift)
                editor.aim(zoom.id, at: model.dragMove(from, by: value.translation, snaps: snaps))
            }
            .onEnded { _ in end() }
    }

    private func cornerGesture(_ corner: AimOverlayModel.Corner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("stage"))
            .onChanged { value in
                let from = begin()
                let depth = model.dragCorner(from, corner, to: value.location)
                editor.setDepth(zoom.id, depth)
                editor.aim(zoom.id, at: model.aimKeeping(from, corner, depth: depth))
            }
            .onEnded { _ in end() }
    }

    private func begin() -> Zoom {
        if let start { return start }
        editor.beginGesture()
        start = zoom
        return zoom
    }

    private func end() {
        editor.endGesture()
        start = nil
    }
}
