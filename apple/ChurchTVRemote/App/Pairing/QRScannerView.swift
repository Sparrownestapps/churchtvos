import SwiftUI
import AVFoundation
import UIKit

/// Camera state for scanning a QR code.
enum CameraAccess: Equatable {
    case checking, ready, denied, unavailable

    /// Looks at the device (no camera on the simulator) and the permission, asking for permission the first time.
    @MainActor static func resolve() async -> CameraAccess {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        default: return .denied
        }
    }
}

/// Live camera preview that reports QR code strings (AVCaptureMetadataOutput, works on every iPhone and iPad).
/// `onScan` is called on the main thread for every new QR string; the caller decides whether it is a pairing code.
struct QRScannerView: UIViewRepresentable {
    var torchOn: Bool
    var onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.configure(view)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.setTorch(torchOn)
    }

    static func dismantleUIView(_ view: PreviewView, coordinator: Coordinator) { coordinator.stop() }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        var onScan: (String) -> Void
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "qr-scanner")
        private var device: AVCaptureDevice?
        private var lastValue: String?
        private var lastTime = Date.distantPast

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func configure(_ view: PreviewView) {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            self.device = device
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
            queue.async { [session] in session.startRunning() }
        }

        func stop() {
            setTorch(false)
            queue.async { [session] in if session.isRunning { session.stopRunning() } }
        }

        func setTorch(_ on: Bool) {
            guard let device, device.hasTorch, (device.torchMode == .on) != on else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            // The same code stays in view for many frames: report it once, and again only after a pause.
            if value == lastValue, Date().timeIntervalSince(lastTime) < 2 { return }
            lastValue = value; lastTime = Date()
            onScan(value)
        }
    }
}

/// True when the device has a torch.
var deviceHasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }
