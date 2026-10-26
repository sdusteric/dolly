import Foundation

public enum Easing {
    /// Cubic bezier (0.45, 0, 0.25, 1), the camera's move in and move out (spec 5.2).
    public static func inOut(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x == 0 || x == 1 { return x }
        let (x1, y1, x2, y2) = (0.45, 0.0, 0.25, 1.0)
        func bezier(_ u: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u
        }
        var lo = 0.0, hi = 1.0, u = x
        for _ in 0..<40 {
            u = (lo + hi) / 2
            if bezier(u, x1, x2) < x { lo = u } else { hi = u }
        }
        return bezier(u, y1, y2)
    }
}
