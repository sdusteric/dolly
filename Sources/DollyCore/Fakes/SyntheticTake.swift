import CoreGraphics
import Foundation

/// Demo takes for tests, shots and dollyctl.
public enum SyntheticTake {
    /// The Shelf Tile Board demo of the mockups: an 848 x 858 pt window, 48.2 s at 60 fps.
    public static func shelfDemo() -> Take {
        Take(
            name: "Shelf Tile Board demo",
            created: Date(timeIntervalSince1970: 1_793_011_320),
            target: .window,
            size: CGSize(width: 848, height: 858),
            pixelScale: 2,
            fps: 60,
            duration: 48.2
        )
    }
}
