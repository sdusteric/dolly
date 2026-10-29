import DollyCore
import Foundation

/// The webcam into `camera.mov`: H.264 at 1280 x 720 (or the closest the device has), 30 fps.
public final class LiveCameraSource: SideSource {
    private let recorder = CaptureRecorder(kind: .camera)
    public init() {}

    public func start(deviceID: String, url: URL, failed: @escaping @Sendable (SideSourceFailure) -> Void) async throws -> Double {
        try await recorder.start(deviceID: deviceID, url: url, failed: failed)
    }

    public func stop() async throws { try await recorder.stop() }
}
