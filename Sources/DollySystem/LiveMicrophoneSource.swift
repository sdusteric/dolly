import DollyCore
import Foundation

/// The microphone into `audio.m4a`: AAC 48 kHz mono.
public final class LiveMicrophoneSource: SideSource {
    private let recorder = CaptureRecorder(kind: .microphone)
    public init() {}

    public func start(deviceID: String, url: URL, failed: @escaping @Sendable (SideSourceFailure) -> Void) async throws -> Double {
        try await recorder.start(deviceID: deviceID, url: url, failed: failed)
    }

    public func stop() async throws { try await recorder.stop() }
}
