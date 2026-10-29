import DollyCore
import SwiftUI

/// The shapes above the stage (studio spec item 1), with the export size beside them.
struct ShapeBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        let shape = editor.take.currentShape
        HStack {
            StudioSegmented(ShapePreset.allCases, selected: shape, label: \.label, itemPadding: 12) { editor.setShape($0) }
                .fixedSize()
                .accessibilityLabel("Shape")
            Spacer(minLength: 12)
            Text(StudioInspectorModel.shapeNote(shape, recording: editor.take.size))
                .monospacedDigit()
                .foregroundStyle(Theme.muted.color)
                .lineLimit(1)
        }
    }
}
