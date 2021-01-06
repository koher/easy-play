import AVFoundation

public struct Frame {
    public let index: Int
    public let time: TimeInterval
    public let pixelBuffer: CVPixelBuffer
}

public protocol VideoSourceProtocol {
    associatedtype Player: PlayerProtocol
    func player() throws -> Player
}

public protocol PlayerProtocol: AnyObject {
    var isPlaying: Bool { get }
    @discardableResult func play(
        _ handler: @escaping (Frame) -> Void,
        completion: ((Error?) -> Void)?
    ) -> Bool
    @discardableResult func pause() -> Bool
}

extension PlayerProtocol {
    @discardableResult
    public func play(_ handler: @escaping (Frame) -> Void) -> Bool {
        play(handler, completion: nil)
    }
}
