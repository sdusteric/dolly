import Foundation

/// Whole-take snapshots; takes are small, so this is simpler than inverse operations.
struct UndoStack {
    static let limit = 200
    private var undos: [Take] = []
    private var redos: [Take] = []

    var canUndo: Bool { !undos.isEmpty }
    var canRedo: Bool { !redos.isEmpty }

    mutating func record(_ before: Take) {
        undos.append(before)
        if undos.count > Self.limit { undos.removeFirst() }
        redos.removeAll()
    }

    mutating func undo(_ current: Take) -> Take? {
        guard let previous = undos.popLast() else { return nil }
        redos.append(current)
        return previous
    }

    mutating func redo(_ current: Take) -> Take? {
        guard let next = redos.popLast() else { return nil }
        undos.append(current)
        return next
    }
}
