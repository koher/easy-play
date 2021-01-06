public protocol Player: AnyObject {
    var isPlaying: Bool { get }
    @discardableResult func play(
        _ handler: @escaping (Frame) -> Void,
        completion: ((Error?) -> Void)?
    ) -> Bool
    @discardableResult func pause() -> Bool
}

extension Player {
    @discardableResult
    public func play(_ handler: @escaping (Frame) -> Void) -> Bool {
        play(handler, completion: nil)
    }
}
