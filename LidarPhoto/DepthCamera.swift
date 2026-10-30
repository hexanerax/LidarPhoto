//
//  DepthCamera.swift
//  LidarPhoto
//

import AVFoundation
import Combine
import Photos
import UIKit

/// Streams LiDAR depth frames, shades them with a chosen gradient, and saves snapshots to Photos.
final class DepthCamera: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case running
        case unsupported
        case denied
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var preview: UIImage?
    @Published private(set) var message: String?
    /// Depth range (meters) mapped onto the gradient; `near` always stays below `far`.
    @Published var nearMeters: Float = DepthRenderer.defaultRange.lowerBound {
        didSet { frameRange = nearMeters...farMeters }
    }
    @Published var farMeters: Float = DepthRenderer.defaultRange.upperBound {
        didSet { frameRange = nearMeters...farMeters }
    }
    @Published var palette: DepthPalette = .greyscale {
        didSet { framePalette = palette }
    }

    private let session = AVCaptureSession()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let sessionQueue = DispatchQueue(label: "depthcamera.session")
    private let depthQueue = DispatchQueue(label: "depthcamera.depth")

    /// Latest frame; written on `depthQueue`, read on the main actor when capturing.
    private nonisolated(unsafe) var latestImage: UIImage?
    private nonisolated(unsafe) var framePalette: DepthPalette = .greyscale
    private nonisolated(unsafe) var frameRange = DepthRenderer.defaultRange
    private nonisolated(unsafe) var lastPublish: CFTimeInterval = 0

    // MARK: Lifecycle

    func start() async {
        guard await requestCameraAccess() else {
            status = .denied
            return
        }
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            status = .unsupported
            return
        }
        let error = await configureAndRun(device: device)
        status = error.map { .failed($0) } ?? .running
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureAndRun(device: AVCaptureDevice) async -> String? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                guard !session.isRunning else { return continuation.resume(returning: nil) }
                do {
                    session.beginConfiguration()
                    session.sessionPreset = .photo

                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input), session.canAddOutput(depthOutput) else {
                        session.commitConfiguration()
                        return continuation.resume(returning: "Could not configure the LiDAR camera.")
                    }
                    session.addInput(input)
                    session.addOutput(depthOutput)

                    // Pick the highest-resolution Float32/Float16 depth format the device offers.
                    try device.lockForConfiguration()
                    if let format = device.activeFormat.supportedDepthDataFormats
                        .filter({ CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32 })
                        .max(by: { $0.formatDescription.dimensions.width < $1.formatDescription.dimensions.width }) {
                        device.activeDepthDataFormat = format
                    }
                    device.unlockForConfiguration()

                    depthOutput.isFilteringEnabled = true
                    depthOutput.alwaysDiscardsLateDepthData = true
                    depthOutput.setDelegate(self, callbackQueue: depthQueue)
                    session.commitConfiguration()

                    session.startRunning()
                    continuation.resume(returning: nil)
                } catch {
                    session.commitConfiguration()
                    continuation.resume(returning: error.localizedDescription)
                }
            }
        }
    }

    // MARK: Capture

    func capture() async {
        guard let image = latestImage, let png = image.pngData() else {
            message = "No depth frame yet."
            return
        }
        let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard granted == .authorized || granted == .limited else {
            message = "Allow Photos access in Settings to save depth maps."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: png, options: nil)
            }
            message = "Depth map saved to Photos."
        } catch {
            message = "Save failed: \(error.localizedDescription)"
        }
    }
}

extension DepthCamera: AVCaptureDepthDataOutputDelegate {
    nonisolated func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        guard let image = DepthRenderer.image(from: depthData, palette: framePalette, range: frameRange) else { return }
        latestImage = image

        // Throttle UI updates to ~30 fps.
        let now = CACurrentMediaTime()
        guard now - lastPublish > 1.0 / 30 else { return }
        lastPublish = now
        Task { @MainActor in self.preview = image }
    }
}
