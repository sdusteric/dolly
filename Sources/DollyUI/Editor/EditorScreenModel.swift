import DollyCore
import Observation
import SwiftUI

/// What the editor window shows: the takes, the selected take's editor model, and the actions the
/// app wires in. Shot mode builds it from fixtures.
@Observable
public final class EditorScreenModel {
    public var entries: [TakeEntry]
    public var totalBytes: Int64
    public var editor: EditorModel?
    public var recordShortcut: String
    /// The sidebar row whose name is being edited in place.
    public var renaming: URL?
    @ObservationIgnored public var posters: [UUID: Image] = [:]
    @ObservationIgnored public var onRecord: () -> Void = {}
    @ObservationIgnored public var onExport: () -> Void = {}
    @ObservationIgnored public var onSelect: (TakeEntry) -> Void = { _ in }
    @ObservationIgnored public var onRename: (TakeEntry, String) -> Void = { _, _ in }
    @ObservationIgnored public var onReveal: (TakeEntry) -> Void = { _ in }
    @ObservationIgnored public var onTrash: (TakeEntry) -> Void = { _ in }

    public init(entries: [TakeEntry], totalBytes: Int64, editor: EditorModel?, recordShortcut: String) {
        self.entries = entries
        self.totalBytes = totalBytes
        self.editor = editor
        self.recordShortcut = recordShortcut
    }

    /// Opening Dolly (launch, the Dock) goes to the Record bar unless a take is open in this run,
    /// so a fresh launch never brings back the last recording.
    public var opensToRecord: Bool { editor == nil }

    func entry(_ row: TakeRow) -> TakeEntry? { entries.first { $0.folder == row.folder } }

    var rows: [TakeRow] { TakesSidebarModel.rows(entries) }
    var footer: String { TakesSidebarModel.footer(count: entries.count, bytes: totalBytes) }
}
