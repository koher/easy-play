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
        _play(handler, completion: nil)
    }

    @discardableResult
    public func play(
        _ handler: @escaping (CVPixelBuffer) -> Void,
        completion: @escaping (Error?) -> Void
    ) -> Bool {
        _play(handler, completion: completion)
    }
    
    private func _play(
        _ handler: @escaping (CVPixelBuffer) -> Void,
        completion: ((Error?) -> Void)?
    ) -> Bool {
        player.play(handler, completion: completion)
    }
    
    @discardableResult
    public func pause() -> Bool {
        player.pause()
    }
}

extension Player {
    public struct VideoSource {
        fileprivate let makePlayer: () throws -> PlayerImplementation
        
        internal init(_ makePlayer: @escaping () throws -> PlayerImplementation) {
            self.makePlayer = makePlayer
        }
    }
}

internal protocol PlayerImplementation: AnyObject {
    var isPlaying: Bool { get }
    func play(
        _ handler: @escaping (CVPixelBuffer) -> Void,
        completion: ((Error?) -> Void)?
    ) -> Bool
    func pause() -> Bool
}
