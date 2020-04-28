import Foundation
import AVFoundation

extension Player.VideoSource {
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
                throw Player.CameraInitializationError.unsupportedPosition(position)
            }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                
                if let focusMode = focusMode {
                    guard device.isFocusModeSupported(focusMode) else {
                        throw Player.CameraInitializationError.unsupportedFocusMode(focusMode)
                    }
                    device.focusMode = focusMode
                } else {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    } else if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }
            } catch let error as Player.CameraInitializationError {
                throw error
            } catch let error {
                throw Player.CameraInitializationError.configurationFailure(error)
            }
            
            return try PlayerImplementationWithCamera(
                device: device,
                sessionPreset: sessionPreset,
                videoSettings: videoSettings
            )
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

internal final class PlayerImplementationWithCamera: PlayerImplementation {
    private let session: AVCaptureSession
    private let sampleBufferDelegate: SampleBufferDelegate
    private var handler: ((CVPixelBuffer) -> Void)?
    
    private let lock: NSRecursiveLock = .init()
    
    init(device: AVCaptureDevice, sessionPreset: AVCaptureSession.Preset, videoSettings: [String: Any]) throws {
        guard device.supportsSessionPreset(sessionPreset) else {
            throw Player.CameraInitializationError.unsupportedSessionPreset(sessionPreset)
        }
        
        let input = try! AVCaptureDeviceInput(device: device)
        
        sampleBufferDelegate = SampleBufferDelegate()
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = videoSettings
        output.setSampleBufferDelegate(sampleBufferDelegate, queue: .serialQueue())
        
        let session = AVCaptureSession()
        do {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            
            session.addInput(input)
            session.addOutput(output)
            session.sessionPreset = sessionPreset
        }
        self.session = session
        
        sampleBufferDelegate.owner = self
    }
    
    var isPlaying: Bool {
        synchronized { _isPlaying }
    }
    
    private var _isPlaying: Bool {
        handler != nil
    }
    
    func play(
        _ handler: @escaping (CVPixelBuffer) -> Void,
        completion: ((Error?) -> Void)?
    ) -> Bool {
        synchronized {
            if _isPlaying { return false }
            
            self.handler = handler
            session.startRunning()
            
            return true
        }
    }
    
    func pause() -> Bool {
        synchronized {
            guard _isPlaying else { return false }
            
            session.stopRunning()
            handler = nil
            
            return true
        }
    }
    
    fileprivate func synchronized<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
    
    private class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: PlayerImplementationWithCamera!
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            owner.synchronized {
                let imageBufferOrNil: CVImageBuffer?
                if #available(OSX 10.15, iOS 13.0, *) {
                    imageBufferOrNil = sampleBuffer.imageBuffer
                } else {
                    imageBufferOrNil = CMSampleBufferGetImageBuffer(sampleBuffer)
                }
                if let imageBuffer = imageBufferOrNil {
                    assert(owner.handler != nil)
                    owner.handler?(imageBuffer)
                }
            }
        }
        
        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        }
    }
}
