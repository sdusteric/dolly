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

    /// The open take's edits could not be saved, so it stays open; `underlying` says why.
    public struct SaveFailed: Error {
        public let underlying: any Error
    }

    /// Saves the open take, then opens the one in `folder`. A take whose folder is gone has nothing
    /// to save; any other failed save throws `SaveFailed` and keeps it open, unless
    /// `discardingEdits`.
    @discardableResult
    public func open(folder: URL, discardingEdits: Bool = false) throws -> EditorModel {
        if !discardingEdits {
            do {
                try save()
            } catch is TakeStore.FolderGone {
            } catch {
                throw SaveFailed(underlying: error)
            }
        }
        var take = try store.load(folder)
        // A picture that is gone draws the default color; the editor shows that too.
        take.look = take.look.resolved(in: folder)
        let editor = EditorModel(take: take, pointer: TakeInputs.pointerPath(take: take, folder: folder))
        self.editor = editor
        self.folder = folder
        return editor
    }

    /// Drops the open take without saving it, for a take that just went to the Trash.
    public func close() {
        editor = nil
        folder = nil
    }

    public func save() throws {
        if let editor { try store.save(editor.take) }
    }
}
