import DollyCore
import SwiftUI

/// The work on the sheet (spec 6.1): the stage with the shape switcher top left, the inspector top
/// right, the timeline across the bottom, 16 pt from the sheet's edges.
public struct EditorWorkspace: View {
    @Bindable var editor: EditorModel
    let stage: AnyView
    let inspector: AnyView
    let timeline: AnyView

    public init(editor: EditorModel, stage: AnyView, inspector: AnyView, timeline: AnyView) {
        self.editor = editor
        self.stage = stage
        self.inspector = inspector
        self.timeline = timeline
    }

    public var body: some View {
        VStack(spacing: Theme.Size.margin) {
            HStack(alignment: .top, spacing: Theme.Size.margin) {
                stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector
                    .frame(width: Theme.Size.inspector)
                    .frame(minHeight: 0, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Size.inspectorRadius))
                    .background(RoundedRectangle(cornerRadius: Theme.Size.inspectorRadius).fill(Theme.raised.color))
            }
            timeline.frame(height: Theme.Size.timeline)
        }
        .padding(Theme.Size.margin)
    }
}
