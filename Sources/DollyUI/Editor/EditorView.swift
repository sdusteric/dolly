import DollyCore
import SwiftUI

/// The editor window (spec 6.1, direction A): toolbar and takes sidebar on the frame color, the
/// work on a sheet inset 8 pt from the right and bottom edges.
public struct EditorView: View {
    @Bindable var model: EditorScreenModel
    let showsWindowControls: Bool
    let workspace: (EditorModel) -> AnyView

    public init(model: EditorScreenModel, showsWindowControls: Bool = false,
                workspace: @escaping (EditorModel) -> AnyView = { _ in AnyView(EmptyView()) }) {
        self.model = model
        self.showsWindowControls = showsWindowControls
        self.workspace = workspace
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolbarView(title: model.editor?.take.name, rename: { model.editor?.renameTake($0) },
                        facts: model.editor.map { TakeFacts.line($0.take) },
                        recordShortcut: model.recordShortcut, canExport: model.editor != nil,
                        showsWindowControls: showsWindowControls, record: model.onRecord, export: model.onExport)
            HStack(spacing: 0) {
                TakesSidebar(rows: model.rows, selected: model.editor?.take.id, footer: model.footer,
                             poster: { row in row.takeID.flatMap { model.posters[$0] } },
                             select: { row in
                                 if let entry = model.entries.first(where: { $0.folder == row.folder }) { model.onSelect(entry) }
                             })
                sheet
                    .padding(.trailing, Theme.Size.sheetInset)
                    .padding(.bottom, Theme.Size.sheetInset)
            }
        }
        .background(Theme.frame.color)
    }

    private var sheet: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Size.sheetRadius).fill(Theme.sheet.color)
            RoundedRectangle(cornerRadius: Theme.Size.sheetRadius).strokeBorder(Theme.border.color, lineWidth: 1)
            if let editor = model.editor {
                workspace(editor)
            } else {
                EmptyStateView(shortcut: model.recordShortcut, record: model.onRecord)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.sheetRadius))
    }
}
