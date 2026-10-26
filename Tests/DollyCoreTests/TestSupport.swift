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

/// A 120 Hz log in global points with presses given as (down, up, x, y). The pointer rests at
/// `rest` between presses. `bit` 1 is the left button, 2 the right.
func makeLog(presses: [(down: Double, up: Double, x: Float, y: Float)], until end: Double,
             rest: (Float, Float) = (400, 400), bit: UInt8 = 1, move: ((Double) -> (Float, Float))? = nil) -> [PointerSample] {
    var out: [PointerSample] = []
    var i = 0
    while Double(i) / 120 <= end + 1e-9 {
        let t = Double(i) / 120
        let press = presses.first { t >= $0.down - 1e-9 && t < $0.up - 1e-9 }
        let p = move?(t) ?? press.map { ($0.x, $0.y) } ?? rest
        out.append(PointerSample(t: t, x: p.0, y: p.1, buttons: press == nil ? 0 : bit, shape: .arrow))
        i += 1
    }
    return out
}

let bigDisplay = RecordingGeometry(target: .display, recordingRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                   windowFrames: [], size: CGSize(width: 1440, height: 900))
