import AVFoundation
import ApplicationServices

public enum Permissions {
    public static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    public static func promptAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
