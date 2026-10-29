import CoreGraphics

/// The gradient backdrops Dolly draws (studio spec item 3). Clip content, so the colors live here
/// rather than in the UI theme. Each is a linear gradient with one soft radial light.
public enum Backdrop {
    public struct Gradient: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        /// The linear gradient's start and end colors.
        public let top: String
        public let bottom: String
        public let light: String
        /// The light's center in unit coordinates of the canvas, top-left origin.
        public let lightAt: CGPoint
        /// CSS degrees: 180 runs straight down.
        public let angle: Double
    }

    public static let gradients: [Gradient] = [
        Gradient(id: "harbor", name: "Harbor", top: "#3E8C8C", bottom: "#0F3B4A", light: "#CFE3D6", lightAt: CGPoint(x: 0.20, y: 0.10), angle: 160),
        Gradient(id: "ember", name: "Ember", top: "#B4442B", bottom: "#3A1410", light: "#F3B562", lightAt: CGPoint(x: 0.80, y: 0.15), angle: 200),
        Gradient(id: "slate", name: "Slate", top: "#46566B", bottom: "#1C2430", light: "#9AA8B8", lightAt: CGPoint(x: 0.15, y: 0.00), angle: 170),
        Gradient(id: "moss", name: "Moss", top: "#556B2F", bottom: "#1E2A1A", light: "#C9C27A", lightAt: CGPoint(x: 0.85, y: 0.05), angle: 190),
        Gradient(id: "rose", name: "Rose", top: "#D2577F", bottom: "#4A1630", light: "#F6C3B5", lightAt: CGPoint(x: 0.25, y: 0.00), angle: 165),
        Gradient(id: "sand", name: "Sand", top: "#D9C3A0", bottom: "#8C6B4A", light: "#F4EBDD", lightAt: CGPoint(x: 0.70, y: 0.00), angle: 180),
    ]

    public static func gradient(_ id: String) -> Gradient? { gradients.first { $0.id == id } }
}
