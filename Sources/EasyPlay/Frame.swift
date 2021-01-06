import Foundation
import CoreVideo

public struct Frame {
    public let index: Int
    public let time: TimeInterval
    public let pixelBuffer: CVPixelBuffer
}
