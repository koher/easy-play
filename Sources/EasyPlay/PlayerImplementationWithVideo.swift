import Foundation
import AVFoundation

public struct Video: VideoSourceProtocol {
    public var asset: AVAsset
    public var outputSettings: [String: Any]?
    
    public init(
        asset: AVAsset,
        outputSettings: [String: Any]? = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
    ) {
        self.asset = asset
        self.outputSettings = outputSettings
    }
    
    public init(
        url: URL,
        outputSettings: [String: Any]? = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
    ) {
        let asset = AVAsset(url: url)
        self.init(asset: asset, outputSettings: outputSettings)
    }
    
    public init(
        path: String,
        outputSettings: [String: Any]? = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
    ) {
        let asset = AVAsset(url: URL(fileURLWithPath: path))
        self.init(asset: asset, outputSettings: outputSettings)
    }
    
    public func player() throws -> _PlayerForVideo {
        try _PlayerForVideo(asset: asset, outputSettings: outputSettings)
    }
}

extension Video {
    public enum InitializationError: Error {
        case noVideoTrack
        case multipleVideoTracks(Int)
        case readerInitializationFailure(Error)
    }
    
    public enum VideoPlayerError: Error {
        case readingFailed(Error)
        case unknown
    }
}

public final class _PlayerForVideo: PlayerProtocol {
    private let videoTrack: AVAssetTrack
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    private var timer: Timer?
    
    private var handler: ((Frame) -> Void)?
    private var completion: ((Error?) -> Void)?
    
    private var frameIndex: Int = 0
    
    private let serialQueue: DispatchQueue = .serialQueue()
    private var isLocking: Bool = false
    
    init(asset: AVAsset, outputSettings: [String: Any]?) throws {
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw Video.InitializationError.noVideoTrack
        }
        guard videoTracks.count == 1 else {
            throw Video.InitializationError
                .multipleVideoTracks(videoTracks.count)
        }
        self.videoTrack = videoTrack
        
        do {
            reader = try AVAssetReader(asset: asset)
        } catch let error {
            throw Video.InitializationError
                .readerInitializationFailure(error)
        }
        output = .init(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
    }
    
    deinit {
        _ = pause()
        reader.cancelReading()
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
            timer = Timer.scheduledTimer(
                withTimeInterval: 1.0 / TimeInterval(videoTrack.nominalFrameRate),
                repeats: true
            ) { [weak self] _ in
                self?.serialQueue.async { [weak self] in
                    guard let self = self else { return }
                    guard let handler = self.handler else { return }
                    
                    guard let sampleBuffer = self.output.copyNextSampleBuffer() else {
                        switch self.reader.status {
                        case .completed:
                            completion?(nil)
                            assert(self._pause())
                        case .failed:
                            if let completion = self.completion {
                                if let error = self.reader.error {
                                    completion(Video.VideoPlayerError.readingFailed(error))
                                } else {
                                    completion(Video.VideoPlayerError.unknown)
                                }
                            }
                            assert(self._pause())
                        case .cancelled:
                            break
                        case .reading:
                            break
                        case .unknown:
                            break
                        @unknown default:
                            break
                        }
                        return
                    }
                    defer { self.frameIndex += 1 }
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
                    guard let imageBuffer = imageBufferOrNil,
                          let timingInfo = timingInfoOrNil else {
                        return
                    }
                    
                    let frame: Frame = .init(
                        index: self.frameIndex,
                        time: CMTimeGetSeconds(timingInfo.presentationTimeStamp),
                        pixelBuffer: imageBuffer
                    )
                    
                    handler(frame)
                }
            }
            
            return true
        }
    }
    
    private func _pause() -> Bool {
        guard _isPlaying else { return false }

        timer?.invalidate()
        timer = nil
        handler = nil
        completion = nil
        
        return true
    }
    
    @discardableResult public func pause() -> Bool {
        serialQueue.sync {
            _pause()
        }
    }
}
