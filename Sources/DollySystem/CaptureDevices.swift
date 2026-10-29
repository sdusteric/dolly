import AVFoundation
import CoreMedia
import DollyCore
import Foundation

/// The cameras and microphones for the Record bar's device menus. Listing them opens nothing.
public enum CaptureDevices {
    public static func cameras() -> [(id: String, name: String)] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
            .devices.map { ($0.uniqueID, $0.localizedName) }
    }

    public static func microphones() -> [(id: String, name: String)] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { ($0.uniqueID, $0.localizedName) }
    }
}

/// One capture device into one file through `AVAssetWriter`, with sample times on the host clock so
/// they line up with the screen's (studio spec, Camera). Used by `LiveCameraSource` and
/// `LiveMicrophoneSource`; never by tests. `@unchecked Sendable`: `state` is only touched under its
/// mutex, and AVFoundation calls the delegate on `queue`.
final class CaptureRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Kind { case camera, microphone }

    struct State {
        var session: AVCaptureSession?
        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var first: CheckedContinuation<Double, any Error>?
        var lastHost: Double?
        var failed: (@Sendable (SideSourceFailure) -> Void)?
        var observers: [any NSObjectProtocol] = []
    }

    static let firstSampleTimeout = 5.0

    let kind: Kind
    let queue = DispatchQueue(label: "dolly.capture")
    private let lock = NSLock()
    private var state = State()

    init(kind: Kind) { self.kind = kind }

    private func withState<T>(_ body: (inout State) -> T) -> T { lock.withLock { body(&state) } }

    func start(deviceID: String, url: URL, failed: @escaping @Sendable (SideSourceFailure) -> Void) async throws -> Double {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { throw RecordingSourceError.couldNotStart("no device") }
        let session = AVCaptureSession()
        session.beginConfiguration()
        let deviceInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(deviceInput) else { throw RecordingSourceError.couldNotStart("input") }
        session.addInput(deviceInput)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { try FileManager.default.removeItem(at: url) }
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        switch kind {
        case .camera:
            if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
            try device.lockForConfiguration()
            let thirty = CMTime(value: 1, timescale: 30)
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && 30 <= $0.maxFrameRate }) {
                device.activeVideoMinFrameDuration = thirty
                device.activeVideoMaxFrameDuration = thirty
            }
            device.unlockForConfiguration()
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { throw RecordingSourceError.couldNotStart("output") }
            session.addOutput(output)
            let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: min(Int(size.width), 1280), AVVideoHeightKey: min(Int(size.height), 720),
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            ])
        case .microphone:
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { throw RecordingSourceError.couldNotStart("output") }
            session.addOutput(output)
            writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
            ])
        }
        session.commitConfiguration()
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingSourceError.couldNotStart("writer") }
        writer.add(input)

        let center = NotificationCenter.default
        let stopped: @Sendable (Notification) -> Void = { [weak self] _ in self?.giveOut(reason: "stopped") }
        let observers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil, using: stopped),
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil, using: stopped),
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil, using: stopped),
        ]
        withState {
            $0.session = session
            $0.writer = writer
            $0.input = input
            $0.failed = failed
            $0.observers = observers
        }
        let first = try await withCheckedThrowingContinuation { continuation in
            withState { $0.first = continuation }
            queue.async { session.startRunning() }
            queue.asyncAfter(deadline: .now() + Self.firstSampleTimeout) { [weak self] in
                self?.withState { $0.first }.map { _ in self?.resumeFirst(with: .failure(RecordingSourceError.couldNotStart("no samples"))) }
            }
        }
        return first
    }

    private func resumeFirst(with result: Result<Double, any Error>) {
        withState { s -> CheckedContinuation<Double, any Error>? in
            defer { s.first = nil }
            return s.first
        }?.resume(with: result)
    }

    private func giveOut(reason: String) {
        let (failed, last) = withState { s in
            defer { s.failed = nil }
            return (s.failed, s.lastHost)
        }
        if let failed, let last { failed(SideSourceFailure(hostTime: last, reason: reason)) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let (session, writer, input) = withState { ($0.session, $0.writer, $0.input) }
        guard let session, let writer, let input else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let host = session.synchronizationClock.map { CMSyncConvertTime(pts, from: $0, to: CMClockGetHostTimeClock()) } ?? pts
        if writer.status == .unknown {
            guard writer.startWriting() else {
                resumeFirst(with: .failure(writer.error ?? RecordingSourceError.couldNotStart("writer")))
                return
            }
            writer.startSession(atSourceTime: pts)
            resumeFirst(with: .success(host.seconds))
        }
        guard writer.status == .writing else { return giveOut(reason: "writer") }
        if input.isReadyForMoreMediaData, input.append(sampleBuffer) {
            withState { $0.lastHost = host.seconds }
        }
    }

    func stop() async throws {
        let (session, writer, input, observers) = withState { s in
            defer {
                s.failed = nil
                s.observers = []
            }
            return (s.session, s.writer, s.input, s.observers)
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                session?.stopRunning()
                done.resume()
            }
        }
        guard let writer, let input, writer.status == .writing else { return }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
