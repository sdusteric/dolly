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
    @ObservationIgnored public var posters: [UUID: Image] = [:]
    @ObservationIgnored public var onRecord: () -> Void = {}
    @ObservationIgnored public var onExport: () -> Void = {}
    @ObservationIgnored public var onSelect: (TakeEntry) -> Void = { _ in }

    public init(entries: [TakeEntry], totalBytes: Int64, editor: EditorModel?, recordShortcut: String) {
        self.entries = entries
        self.totalBytes = totalBytes
        self.editor = editor
        self.recordShortcut = recordShortcut
    }

    /// Opening Dolly with no takes goes straight to the Record bar: the editor has nothing to show.
    public var opensToRecord: Bool { entries.isEmpty }

    var rows: [TakeRow] { TakesSidebarModel.rows(entries) }
    var footer: String { TakesSidebarModel.footer(count: entries.count, bytes: totalBytes) }
}
