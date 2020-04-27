import AVFoundation

public final class Player {
    private let player: PlayerImplementation
    
    public init(videoSource: VideoSource) throws {
        player = try videoSource.makePlayer()
    }

    public var isPlaying: Bool {
        player.isPlaying
    }
    
    @discardableResult
    public func play(_ handler: @escaping (CVPixelBuffer) -> Void) -> Bool {
        player.play(handler)
    }
    
    @discardableResult
    public func pause() -> Bool {
        player.pause()
    }
}

extension Player {
    public struct VideoSource {
        fileprivate let makePlayer: () throws -> PlayerImplementation
        
        private init(_ makePlayer: @escaping () throws -> PlayerImplementation) {
            self.makePlayer = makePlayer
        }
        
        public static func camera(
            device: AVCaptureDevice,
            sessionPreset: AVCaptureSession.Preset = .vga640x480,
            videoSettings: [String: Any] = [:]
        ) -> Self {
            Self {
                try PlayerImplementationWithCamera(
                    device: device,
                    sessionPreset: sessionPreset,
                    videoSettings: videoSettings
                )
            }
        }
        
        public static func camera(
            position: AVCaptureDevice.Position = .back,
            focusMode: AVCaptureDevice.FocusMode? = nil,
            sessionPreset: AVCaptureSession.Preset = .vga640x480,
            videoSettings: [String: Any] = [:]
        ) -> Self {
            Self {
                var deviceOrNil: AVCaptureDevice? = nil
                if #available(OSX 10.15, iOS 10.0, *) {
                    deviceOrNil = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                } else {
                    for aDevice in AVCaptureDevice.devices(for: .video) {
                        if aDevice.position == position {
                            deviceOrNil = aDevice
                            break
                        }
                    }
                }
                guard let device = deviceOrNil else {
                    throw CameraInitializationError.unsupportedPosition(position)
                }

                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    
                    if let focusMode = focusMode {
                        guard device.isFocusModeSupported(focusMode) else {
                            throw CameraInitializationError.unsupportedFocusMode(focusMode)
                        }
                        device.focusMode = focusMode
                    } else {
                        if device.isFocusModeSupported(.continuousAutoFocus) {
                            device.focusMode = .continuousAutoFocus
                        } else if device.isFocusModeSupported(.autoFocus) {
                            device.focusMode = .autoFocus
                        }
                    }
                } catch let error as CameraInitializationError {
                    throw error
                } catch let error {
                    throw CameraInitializationError.configurationFailure(error)
                }
                
                return try PlayerImplementationWithCamera(
                    device: device,
                    sessionPreset: sessionPreset,
                    videoSettings: videoSettings
                )
            }
        }
    }
}

extension Player {
    public enum CameraInitializationError: Error {
        case unsupportedPosition(AVCaptureDevice.Position)
        case unsupportedFocusMode(AVCaptureDevice.FocusMode)
        case unsupportedSessionPreset(AVCaptureSession.Preset)
        case configurationFailure(Error)
    }
}

internal protocol PlayerImplementation: AnyObject {
    var isPlaying: Bool { get }
    func play(_ handler: @escaping (CVPixelBuffer) -> Void) -> Bool
    func pause() -> Bool
}
