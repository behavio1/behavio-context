@preconcurrency import AVFoundation
import Foundation

public actor SystemCaptureAuthorization: CaptureAuthorization {

    public init() {}

    public func requestMicrophoneAccess() async -> Bool {
        await requestAccess(for: .audio)
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}
