import CoreGraphics
import Foundation
@testable import DollyCore

func approx(_ a: Double, _ b: Double, tol: Double = 0.001) -> Bool { abs(a - b) <= tol }
func approx(_ a: [Double], _ b: [Double], tol: Double = 0.001) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { approx($0, $1, tol: tol) }
}
func approx(_ a: CGPoint, _ b: CGPoint, tol: Double = 0.01) -> Bool {
    approx(a.x, b.x, tol: tol) && approx(a.y, b.y, tol: tol)
}

func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "dolly-\(UUID().uuidString)-\(name)")
}

enum Fixtures {
    static func url(_ name: String) throws -> URL {
        guard let base = Bundle.module.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        return base.appending(path: "Fixtures/\(name)")
    }

    /// The Shelf demo log: a window at global (0, 0, 848, 858), recording start host time 0.
    static func shelfDemoSamples() throws -> [PointerSample] {
        try PointerLog.fromCSV(String(contentsOf: url("shelf-demo.csv"), encoding: .utf8))
    }

    static let shelfGeometry = RecordingGeometry(
        target: .window, recordingRect: .zero,
        windowFrames: [WindowFrameSample(t: 0, frame: CGRect(x: 0, y: 0, width: 848, height: 858))],
        size: CGSize(width: 848, height: 858)
    )
}
