import Foundation

/// The take open in the editor. Every open reads take.json from disk, so a take reopened from
/// the sidebar has its latest saved edits, never the copy the sidebar listed earlier.
public final class TakeSession {
    public let store: TakeStore
    public private(set) var editor: EditorModel?
    public private(set) var folder: URL?

    public init(store: TakeStore) {
        self.store = store
    }

    /// Saves the open take, then opens the one in `folder`.
    @discardableResult
    public func open(folder: URL) throws -> EditorModel {
        try save()
        var take = try store.load(folder)
        // A picture that is gone draws the default color; the editor shows that too.
        take.look = take.look.resolved(in: folder)
        let editor = EditorModel(take: take, pointer: TakeInputs.pointerPath(take: take, folder: folder))
        self.editor = editor
        self.folder = folder
        return editor
    }

    public func save() throws {
        if let editor { try store.save(editor.take) }
    }
}
