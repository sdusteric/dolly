import Foundation

/// Camera or microphone access as macOS reports it, read without prompting.
public enum DevicePermission: Sendable, Hashable { case allowed, denied, notAsked }

/// When a side device gave out mid-take: the host time of its last good sample, and why.
public struct SideSourceFailure: Sendable, Hashable {
    public var hostTime: Double
    public var reason: String
    public init(hostTime: Double, reason: String) {
        self.hostTime = hostTime
        self.reason = reason
    }
}

/// The camera or the microphone, recorded to its own file beside the screen on the same host clock
/// (studio spec, Camera). `LiveCameraSource` and `LiveMicrophoneSource` (DollySystem) are the real
/// ones; `FakeSideSource` writes a stand-in file.
public protocol SideSource: AnyObject, Sendable {
    /// Opens the device and returns the host time of its first sample. `failed` is called at most
    /// once if the device stops before `stop`; the file keeps what was written.
    func start(deviceID: String, url: URL, failed: @escaping @Sendable (SideSourceFailure) -> Void) async throws -> Double
    func stop() async throws
}
