import AppKit
import AVFoundation
import DollyCore

/// The Record bar's live camera preview: an `AVCaptureSession` into a mirrored preview layer, opened
/// only while the Camera switch is on and the bar is open. Never used by tests or shots.
@MainActor
public final class CameraPreview {
    private var session: AVCaptureSession?
    private let queue = DispatchQueue(label: "dolly.camera.preview")

    public init() {}

    /// The preview's view, or nil when the camera cannot open. An empty ID is the default camera.
    public func start(deviceID: String?) -> NSView? {
        stop()
        let device = deviceID.flatMap { $0.isEmpty ? nil : AVCaptureDevice(uniqueID: $0) } ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        let session = AVCaptureSession()
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        let view = NSView()
        view.wantsLayer = true
        view.layer = layer
        self.session = session
        nonisolated(unsafe) let running = session
        queue.async { running.startRunning() }
        return view
    }

    public func stop() {
        guard let session else { return }
        self.session = nil
        nonisolated(unsafe) let stopping = session
        queue.async { stopping.stopRunning() }
    }
}
