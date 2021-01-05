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
    private var handler: ((Player.Frame) -> Void)?
    
    private var initialTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var frameIndex: Int = 0
    
    private let serialQueue: DispatchQueue = .serialQueue()
    
    init(device: AVCaptureDevice, sessionPreset: AVCaptureSession.Preset, videoSettings: [String: Any]) throws {
        guard device.supportsSessionPreset(sessionPreset) else {
            throw Player.CameraInitializationError.unsupportedSessionPreset(sessionPreset)
        }
        
        let input = try! AVCaptureDeviceInput(device: device)
        
        sampleBufferDelegate = SampleBufferDelegate()
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = videoSettings
        output.setSampleBufferDelegate(sampleBufferDelegate, queue: serialQueue)
        
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
        serialQueue.sync { _isPlaying }
    }
    
    private var _isPlaying: Bool {
        handler != nil
    }
    
    func play(
        _ handler: @escaping (Player.Frame) -> Void,
        completion: ((Error?) -> Void)?
    ) -> Bool {
        serialQueue.sync {
            if _isPlaying { return false }
            
            self.handler = handler
            session.startRunning()
            
            return true
        }
    }
    
    func pause() -> Bool {
        serialQueue.sync {
            guard _isPlaying else { return false }
            
            session.stopRunning()
            handler = nil
            
            return true
        }
    }
    
    private class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: PlayerImplementationWithCamera?
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let owner = self.owner else { return }
            defer { owner.frameIndex += 1 }
            let imageBufferOrNil: CVImageBuffer?
            let timingInfoOrNil: CMSampleTimingInfo?
            if #available(OSX 10.15, iOS 13.0, *) {
                imageBufferOrNil = sampleBuffer.imageBuffer
                timingInfoOrNil = try? sampleBuffer.sampleTimingInfo(at: 0)
            } else {
                imageBufferOrNil = CMSampleBufferGetImageBuffer(sampleBuffer)
                var timingInfo: CMSampleTimingInfo = .init()
                if CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo) == 0 {
                    timingInfoOrNil = timingInfo
                } else {
                    timingInfoOrNil = nil
                }
            }
            if let imageBuffer = imageBufferOrNil,
               let timingInfo = timingInfoOrNil {
                assert(owner.handler != nil)
                
                let time: TimeInterval
                let currentTime: TimeInterval = CMTimeGetSeconds(timingInfo.presentationTimeStamp)
                if let initialTime = owner.initialTime {
                    time = currentTime - initialTime
                } else {
                    time = 0
                    owner.initialTime = currentTime
                }
                owner.lastTime = time

                owner.handler?(
                    Player.Frame(
                        index: owner.frameIndex,
                        time: time,
                        pixelBuffer: imageBuffer
                    )
                )
            }
        }
        
        func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        }
    }
}
