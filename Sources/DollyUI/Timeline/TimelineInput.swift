import DollyCore
import SwiftUI

/// Play, pause and shuttle, from the app's player. Shot mode passes none.
public protocol PlaybackControlling: AnyObject {
    func togglePlay()
    /// Negative is backward; 0 pauses.
    func shuttle(_ rate: Double)
}

nonisolated public enum TimelineAction: Hashable, Sendable {
    case addZoom, addCaption, addCut, removeSelected, selectNext, togglePlay, undo, redo
    /// nil is one frame forward or back by the key; the sign comes from the key.
    case step(seconds: Double?)
    case stepBack
    case shuttle(Double)
}

/// The timeline's keys (spec 6.3): Space, J K L, arrows (Shift one second), Tab, Z, C, X, Delete, undo.
public enum TimelineInput {
    nonisolated public static func action(key: KeyEquivalent, shift: Bool, command: Bool) -> TimelineAction? {
        switch key {
        case "z" where command: return shift ? .redo : .undo
        case "z", "Z": return command ? nil : .addZoom
        case "c", "C": return command ? nil : .addCaption
        case "x", "X": return command ? nil : .addCut
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
        case .addCaption: editor.addCaption(at: editor.playhead)
        case .addCut: editor.addCut(at: editor.playhead)
        case .removeSelected: editor.removeSelected()
        case .selectNext: editor.selectNext()
        case .togglePlay: playback?.togglePlay()
        case .undo: editor.undo()
        case .redo: editor.redo()
        case .step(let seconds): move(seconds ?? frame)
        case .stepBack: move(-frame)
        case .shuttle(let rate): playback?.shuttle(rate)
        }
    }

    /// The end of a press on the camera or captions lane. On the camera bar a drag hides that
    /// stretch and a click selects the camera; a click on a hidden stretch shows it again; a click on
    /// the empty captions lane moves the playhead.
    public static func finishDrag(_ hit: TimelineHit, from t0: Double, to t1: Double, moved: Bool, editor: EditorModel) {
        switch hit {
        case .cameraBar:
            if moved {
                editor.hideCamera(from: t0, to: t1)
            } else {
                editor.selectCamera()
                editor.playhead = t0
            }
        case .cameraGap(let i, .body) where !moved:
            editor.showCamera(range: i)
        case .emptyCaptionLane:
            editor.select(nil)
            editor.playhead = t0
        default:
            break
        }
    }
}
