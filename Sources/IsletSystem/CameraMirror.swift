import AVFoundation
import IsletCore

/// The camera behind the Mirror page. The capture session runs only between `start()` and
/// `stop()`, which the app calls as the page opens and closes, so the camera (and its light)
/// is on exactly while the page shows. Frames go to the preview layer and nowhere else: nothing
/// is recorded, kept or sent.
public final class CameraMirror: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case off
        case running
        /// No camera is connected (a Mac mini, or the lid closed with no other camera).
        case noCamera
        /// macOS hasn't been asked yet, or said no.
        case needsAccess
    }

    /// What macOS allows. Reading it never asks.
    public static var access: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    /// Asks macOS (it shows its own prompt the first time), then reports on the main thread.
    public static func requestAccess(_ completion: @escaping (PermissionStatus) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { completion(access) }
        }
    }

    public let session = AVCaptureSession()
    /// Called on the main thread when the state changes.
    public var onChange: ((State) -> Void)?
    public private(set) var state: State = .off

    private let queue = DispatchQueue(label: "islet.camera", qos: .userInitiated)
    private var configured = false
    /// Bumped by every start and stop, so a start that finishes after a stop turns itself off.
    private var generation = 0

    public init() {}

    deinit { session.stopRunning() }

    /// Starts the camera if macOS allows it. Safe to call again while running.
    public func start() {
        guard Self.access == .granted else { return set(.needsAccess) }
        generation += 1
        let mine = generation
        queue.async { [self] in
            let ok = configured || configure()
            configured = ok
            guard ok else {
                DispatchQueue.main.async { if self.generation == mine { self.set(.noCamera) } }
                return
            }
            if !session.isRunning { session.startRunning() }
            // A stop that came meanwhile is queued behind this and turns the camera off again;
            // only the latest start reports.
            DispatchQueue.main.async { if self.generation == mine { self.set(.running) } }
        }
    }

    public func stop() {
        generation += 1
        if state == .running || state == .noCamera { set(.off) }
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func set(_ new: State) {
        guard new != state else { return }
        state = new
        onChange?(new)
    }

    /// The default camera as the input, at a size that suits a small preview.
    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }
}
