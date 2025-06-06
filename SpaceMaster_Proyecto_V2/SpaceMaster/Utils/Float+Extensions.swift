import Foundation

public extension Float {
    static func getRandom(from min: Float = -1.0, to max: Float = 1.0) -> Float {
        let fraction = Float(arc4random()) / Float(UInt32.max)
        return (fraction * (max - min)) + min
    }
}
