import CoreGraphics
import Foundation
import Testing
@testable import DollyCore
@testable import DollyUI

/// The preview player on a real fixture movie. Nothing is shown and nothing plays.
@MainActor @Suite struct PreviewPlayerTests {
    @Test func exportPlatesHaveEveryShapeAtItsSize() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "dolly-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await SyntheticTake.writeMovie(seconds: 2, fps: 30, variableRate: false, to: folder.appending(path: TakeStore.movieName))
        let take = Take(name: "Plates", target: .display, size: CGSize(width: 1440, height: 900), pixelScale: 1, fps: 30, duration: 2)
        let editor = EditorModel(take: take, pointer: nil)
        editor.playhead = 1
        let preview = PreviewPlayer()
        preview.load(editor: editor, folder: folder)
        defer { preview.unload() }
        let stills = await preview.outputStills()
        #expect(Set(stills.keys) == Set(ShapePreset.allCases))
        for shape in ShapePreset.allCases {
            let size = shape.pixelSize(recording: take.size)
            #expect(stills[shape]?.width == size.width && stills[shape]?.height == size.height, "\(shape)")
        }
    }
}
