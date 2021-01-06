public protocol VideoSourceProtocol {
    associatedtype Player: PlayerProtocol
    func player() throws -> Player
}
