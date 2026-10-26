import Foundation

/// How times read in the UI: `0:08.6` on the timeline, `2.7 s` in prose, `0:48` in lists.
public enum TimeText {
    public static func clock(_ s: Double) -> String {
        let tenths = Int((max(0, s) * 10).rounded())
        let seconds = Double(tenths % 600) / 10
        let minutes = tenths / 600
        let secondText = String(format: "%04.1f", seconds)
        return minutes >= 60
            ? String(format: "%d:%02d:", minutes / 60, minutes % 60) + secondText
            : "\(minutes):" + secondText
    }
}
