import Foundation
import AVFoundation

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
        output.setSampleBufferDelegate(sampleBufferDelegate, queue: .global(qos: .userInteractive))
        
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
    
    func play(_ handler: @escaping (CVPixelBuffer) -> Void) -> Bool {
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
