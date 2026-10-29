import DollyCore
import SwiftUI

/// Camera (studio spec, Camera tab): the webcam bubble's shape, size, corner and switches.
struct CameraTab: View {
    @Bindable var editor: EditorModel
    @Environment(\.dollyShot) private var shot

    static let noCamera = "This take has no camera. Turn on Camera in the Record bar before your next take."
    static let dragHint = "Drag the camera on the stage to move it"

    private var rows: StudioRows { StudioRows(shot: shot) }

    var body: some View {
        if let camera = editor.take.camera {
            VStack(alignment: .leading, spacing: 0) {
                content(camera)
                Spacer(minLength: 12)
                Text(Self.dragHint).font(Theme.Font.meta).foregroundStyle(Theme.muted.color)
            }
        } else {
            Text(Self.noCamera).foregroundStyle(Theme.muted.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func content(_ camera: CameraTrack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            rows.toggle("Show camera", camera.shown) { v in editor.setCamera { $0.shown = v } }
            StudioSegmented(CameraTrack.Shape.allCases, selected: camera.shape, label: { $0 == .circle ? "Circle" : "Rounded" }) { s in
                editor.setCamera { $0.shape = s }
            }
            VStack(alignment: .leading, spacing: 4) {
                rows.slider("Size", text: StudioInspectorModel.percentText(camera.size), value: camera.size,
                            range: CameraTrack.sizeRange, step: 0.01, editor: editor) { v in editor.setCamera { $0.size = v } }
                HStack {
                    Text("10%")
                    Spacer()
                    Text("25%")
                    Spacer()
                    Text("40%")
                }
                .font(Theme.Font.tick).monospacedDigit().foregroundStyle(Theme.muted.color)
            }
            HStack {
                Text("Corner").font(Theme.Font.bodyMedium)
                Spacer()
                cornerPicker(camera)
            }
            rows.toggle("Border", camera.border) { v in editor.setCamera { $0.border = v } }
            rows.toggle("Shrink during zooms", camera.shrinkDuringZooms) { v in editor.setCamera { $0.shrinkDuringZooms = v } }
            rows.toggle("Mirror", camera.mirror) { v in editor.setCamera { $0.mirror = v } }
        }
    }

    /// Four squares in the corners' layout; the chosen one is filled. A dragged spot has none.
    private func cornerPicker(_ camera: CameraTrack) -> some View {
        let rows: [[CameraTrack.Corner]] = [[.topLeft, .topRight], [.bottomLeft, .bottomRight]]
        return VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { corner in
                        let on = camera.point == nil && camera.corner == corner
                        Button {
                            editor.setCamera {
                                $0.corner = corner
                                $0.point = nil
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(on ? Theme.ink.color : Theme.sheet.color)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(on ? Theme.ink.color : Theme.control.color, lineWidth: 1))
                                .frame(width: 22, height: 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Self.cornerName(corner))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
    }

    static func cornerName(_ corner: CameraTrack.Corner) -> String {
        switch corner {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}
