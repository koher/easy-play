import Dispatch

internal extension DispatchQueue {
    static func make(isConcurrent: Bool = false) -> DispatchQueue {
        .init(label: "org.koherent.EasyPlay", qos: .userInteractive, attributes: isConcurrent ? .concurrent : [], autoreleaseFrequency: .inherit, target: nil)
    }
}
