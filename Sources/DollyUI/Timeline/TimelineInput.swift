import DollyCore
import SwiftUI

/// Play, pause and shuttle, from the app's player. Shot mode passes none.
public protocol PlaybackControlling: AnyObject {
    func togglePlay()
    /// Negative is backward; 0 pauses.
    func shuttle(_ rate: Double)
}

nonisolated public enum TimelineAction: Hashable, Sendable {
    case addZoom, removeSelected, selectNext, togglePlay, undo, redo
    /// nil is one frame forward or back by the key; the sign comes from the key.
    case step(seconds: Double?)
    case stepBack
    case shuttle(Double)
}

/// The timeline's keys (spec 6.3): Space, J K L, arrows (Shift one second), Tab, Z, Delete, undo.
public enum TimelineInput {
    nonisolated public static func action(key: KeyEquivalent, shift: Bool, command: Bool) -> TimelineAction? {
        switch key {
        case "z" where command: return shift ? .redo : .undo
        case "z", "Z": return command ? nil : .addZoom
        case .delete, .deleteForward: return .removeSelected
        case .tab: return .selectNext
        case " ", .space: return .togglePlay
        case "j": return .shuttle(-1)
        case "k": return .shuttle(0)
        case "l": return .shuttle(1)
        case .leftArrow: return shift ? .step(seconds: -1) : .stepBack
        case .rightArrow: return shift ? .step(seconds: 1) : .step(seconds: nil)
        default: return nil
        }
    }

    public static func apply(_ action: TimelineAction, to editor: EditorModel, playback: (any PlaybackControlling)?) {
        let frame = 1 / Double(max(editor.take.fps, 1))
        let range = editor.take.trim
        func move(_ dt: Double) { editor.playhead = min(max(editor.playhead + dt, range.lowerBound), range.upperBound) }
        switch action {
        case .addZoom: editor.addZoom(at: editor.playhead)
        case .removeSelected: if let id = editor.selectedZoom { editor.remove(id) }
        case .selectNext: editor.selectNext()
        case .togglePlay: playback?.togglePlay()
        case .undo: editor.undo()
        case .redo: editor.redo()
        case .step(let seconds): move(seconds ?? frame)
        case .stepBack: move(-frame)
        case .shuttle(let rate): playback?.shuttle(rate)
        }
    }
}
