import Foundation
import AVFoundation

extension Player.VideoSource {
    public static func video(
        asset: AVAsset,
        outputSettings: [String: Any]? = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
    ) -> Self {
        .init {
            try PlayerImplementationWithVideo(asset: asset, outputSettings: outputSettings)
        }
    }
    
    public static func video(
        url: URL,
        outputSettings: [String: Any]? = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
    ) -> Self {
        .init {
            let asset: AVAsset = .init(url: url)
            return try PlayerImplementationWithVideo(asset: asset, outputSettings: outputSettings)
        }
    }
    
    public static func video(
        path: String,
        outputSettings: [String: Any]? = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
    ) -> Self {
        .init {
            let asset: AVAsset = .init(url: URL(fileURLWithPath: path))
            return try PlayerImplementationWithVideo(asset: asset, outputSettings: outputSettings)
        }
    }
}

extension Player {
    public enum VideoInitializationError: Error {
        case noVideoTrack
        case multipleVideoTracks(Int)
        case readerInitializationFailure(Error)
    }
    
    public enum VideoPlayerError: Error {
        case readingFailed(Error)
        case unknown
    }
}

internal final class PlayerImplementationWithVideo: PlayerImplementation {
    private let videoTrack: AVAssetTrack
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    private var timer: Timer?
    
    private var handler: ((CVPixelBuffer) -> Void)?
    private var completion: ((Error?) -> Void)?
    
    private let serialQueue: DispatchQueue = .serialQueue()
    private var isLocking: Bool = false
    
    init(asset: AVAsset, outputSettings: [String: Any]?) throws {
        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw Player.VideoInitializationError.noVideoTrack
        }
        guard videoTracks.count == 1 else {
            throw Player.VideoInitializationError
                .multipleVideoTracks(videoTracks.count)
        }
        self.videoTrack = videoTrack
        
        do {
            reader = try AVAssetReader(asset: asset)
        } catch let error {
            throw Player.VideoInitializationError
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

    var isPlaying: Bool {
        serialQueue.sync { _isPlaying }
    }
    
    private var _isPlaying: Bool {
        handler != nil
    }

    func play(
        _ handler: @escaping (CVPixelBuffer) -> Void,
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
                    
                    guard let sampleBuffer = self.output.copyNextSampleBuffer() else {
                        switch self.reader.status {
                        case .completed:
                            completion?(nil)
                            assert(self._pause())
                        case .failed:
                            if let completion = self.completion {
                                if let error = self.reader.error {
                                    completion(Player.VideoPlayerError.readingFailed(error))
                                } else {
                                    completion(Player.VideoPlayerError.unknown)
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
                    let imageBufferOrNil: CVImageBuffer?
                    if #available(OSX 10.15, iOS 13.0, *) {
                        imageBufferOrNil = sampleBuffer.imageBuffer
                    } else {
                        imageBufferOrNil = CMSampleBufferGetImageBuffer(sampleBuffer)
                    }
                    guard let imageBuffer = imageBufferOrNil else {
                        return
                    }
                    
                    if self.isLocking { return }
                    self.serialQueue.async { [weak self] in
                        guard let self = self else { return }
                        guard self._isPlaying else { return }
                        self.isLocking = true
                        defer { self.isLocking = false }
                        assert(self.handler != nil)
                        self.handler?(imageBuffer)
                    }
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
    
    func pause() -> Bool {
        serialQueue.sync {
            _pause()
        }
    }
}
