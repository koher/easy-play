import Dispatch

internal extension DispatchQueue {
    static func serialQueue() -> DispatchQueue {
        .init(label: "org.koherent.EasyPlay", qos: .userInteractive, attributes: [], autoreleaseFrequency: .inherit, target: nil)
    }
}
