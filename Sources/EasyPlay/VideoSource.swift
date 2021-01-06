public protocol VideoSource {
    associatedtype Player: EasyPlay.Player
    func player() throws -> Player
}
