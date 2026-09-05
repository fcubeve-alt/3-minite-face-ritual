import Foundation

// MARK: - 最小 2D 几何类型
// 不用 CGPoint：Core 必须能在无 CoreGraphics 的环境编译（Linux CI / 纯 swift test）。
// App 层通过 `Point2D.cgPoint` 桥接。

public struct Point2D: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)

    public func distance(to other: Point2D) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }

    public func lerp(to other: Point2D, t: Double) -> Point2D {
        Point2D(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }

    public static func + (lhs: Point2D, rhs: Vector2D) -> Point2D {
        Point2D(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    public static func - (lhs: Point2D, rhs: Point2D) -> Vector2D {
        Vector2D(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }
}

public struct Vector2D: Hashable, Codable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = Vector2D(dx: 0, dy: 0)

    public var length: Double { (dx * dx + dy * dy).squareRoot() }

    public var normalized: Vector2D {
        let len = length
        guard len > 1e-9 else { return .zero }
        return Vector2D(dx: dx / len, dy: dy / len)
    }

    /// 屏幕坐标系（y 向下）中顺时针旋转 90°。
    public var rotatedClockwise90: Vector2D { Vector2D(dx: -dy, dy: dx) }

    /// 相对 +x 轴的角度，弧度。
    public var angle: Double { atan2(dy, dx) }

    public static func * (lhs: Vector2D, rhs: Double) -> Vector2D {
        Vector2D(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }

    public static func + (lhs: Vector2D, rhs: Vector2D) -> Vector2D {
        Vector2D(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    public static func rotated(byRadians angle: Double, length: Double) -> Vector2D {
        Vector2D(dx: cos(angle) * length, dy: sin(angle) * length)
    }
}

public struct Size2D: Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size2D(width: 0, height: 0)
}

public struct Rect2D: Hashable, Codable, Sendable {
    public var origin: Point2D
    public var size: Size2D

    public init(origin: Point2D, size: Size2D) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: Point2D(x: x, y: y), size: Size2D(width: width, height: height))
    }

    public static let zero = Rect2D(x: 0, y: 0, width: 0, height: 0)

    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }
    public var center: Point2D { Point2D(x: midX, y: midY) }

    public func contains(_ point: Point2D) -> Bool {
        point.x >= origin.x && point.x <= origin.x + size.width
            && point.y >= origin.y && point.y <= origin.y + size.height
    }
}

@inlinable
public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}
