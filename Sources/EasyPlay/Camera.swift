import Foundation
import AVFoundation

public struct Camera: VideoSourceProtocol {
    private enum DeviceSettings {
        case device(AVCaptureDevice)
        case position(AVCaptureDevice.Position, focusMode: AVCaptureDevice.FocusMode?)
    }
    
    private let deviceSettings: DeviceSettings
    public var sessionPreset: AVCaptureSession.Preset
    public var videoSettings: [String: Any]
    
    public init(
        device: AVCaptureDevice,
        sessionPreset: AVCaptureSession.Preset = .vga640x480,
        videoSettings: [String: Any] = [:]
    ) {
        self.deviceSettings = .device(device)
        self.sessionPreset = sessionPreset
        self.videoSettings = videoSettings
    }
    
    public init(
        position: AVCaptureDevice.Position = .back,
        focusMode: AVCaptureDevice.FocusMode? = nil,
        sessionPreset: AVCaptureSession.Preset = .vga640x480,
        videoSettings: [String: Any] = [:]
    ) {
        self.deviceSettings = .position(position, focusMode: focusMode)
        self.sessionPreset = sessionPreset
        self.videoSettings = videoSettings
    }
    
    public func player() throws -> some PlayerProtocol {
        let device: AVCaptureDevice
        switch deviceSettings {
        case .device(let designatedDevice):
            device = designatedDevice
        case .position(let position, focusMode: let focusMode):
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
            guard let deviceToSetUp = deviceOrNil else {
                throw InitializationError.unsupportedPosition(position)
            }

            do {
                try deviceToSetUp.lockForConfiguration()
                defer { deviceToSetUp.unlockForConfiguration() }
                
                if let focusMode = focusMode {
                    guard deviceToSetUp.isFocusModeSupported(focusMode) else {
                        throw InitializationError.unsupportedFocusMode(focusMode)
                    }
                    deviceToSetUp.focusMode = focusMode
                } else {
                    if deviceToSetUp.isFocusModeSupported(.continuousAutoFocus) {
                        deviceToSetUp.focusMode = .continuousAutoFocus
                    } else if deviceToSetUp.isFocusModeSupported(.autoFocus) {
                        deviceToSetUp.focusMode = .autoFocus
                    }
                }
            } catch let error as InitializationError {
                throw error
            } catch let error {
                throw InitializationError.configurationFailure(error)
            }
            
            device = deviceToSetUp
        }
        
        return try _PlayerForCamera(
            device: device,
            sessionPreset: sessionPreset,
            videoSettings: videoSettings
        )
    }
}

extension Camera {
    public enum InitializationError: Error {
        case unsupportedPosition(AVCaptureDevice.Position)
        case unsupportedFocusMode(AVCaptureDevice.FocusMode)
        case unsupportedSessionPreset(AVCaptureSession.Preset)
        case configurationFailure(Error)
    }
}

private final class _PlayerForCamera: PlayerProtocol {
    private let session: AVCaptureSession
    private let sampleBufferDelegate: SampleBufferDelegate
    private var handler: ((Frame) -> Void)?
    
    private var initialTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var frameIndex: Int = 0
    
    private let serialQueue: DispatchQueue = .serialQueue()
    
    init(device: AVCaptureDevice, sessionPreset: AVCaptureSession.Preset, videoSettings: [String: Any]) throws {
        guard device.supportsSessionPreset(sessionPreset) else {
            throw Camera.InitializationError.unsupportedSessionPreset(sessionPreset)
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
    
    public var isPlaying: Bool {
        serialQueue.sync { _isPlaying }
    }
    
    private var _isPlaying: Bool {
        handler != nil
    }
    
    @discardableResult public func play(
        _ handler: @escaping (Frame) -> Void,
        completion: ((Error?) -> Void)?
    ) -> Bool {
        serialQueue.sync {
            if _isPlaying { return false }
            
            self.handler = handler
            session.startRunning()
            
            return true
        }
    }
    
    @discardableResult public func pause() -> Bool {
        serialQueue.sync {
            guard _isPlaying else { return false }
            
            session.stopRunning()
            handler = nil
            
            return true
        }
    }
    
    private class SampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var owner: _PlayerForCamera?
        
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
                    Frame(
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
