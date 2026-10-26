import Foundation

public enum DiskLimits {
    /// Refuse to start under 2 GB free; stop cleanly under 500 MB (Snap's rule, spec 4.2).
    public static let startBytes: Int64 = 2_000_000_000
    public static let stopBytes: Int64 = 500_000_000
}
