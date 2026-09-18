import Foundation

/// A point in the 2D drawing canvas. Y grows downward, matching every 2D
/// drawing API we target (SwiftUI `Canvas`, SVG, Core Graphics).
public struct Point2: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2(0, 0)

    public static func + (a: Point2, b: Point2) -> Point2 { Point2(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2, b: Point2) -> Point2 { Point2(a.x - b.x, a.y - b.y) }
    public static func * (p: Point2, k: Double) -> Point2 { Point2(p.x * k, p.y * k) }
    public static func / (p: Point2, k: Double) -> Point2 { Point2(p.x / k, p.y / k) }

    public func lerp(to other: Point2, _ t: Double) -> Point2 {
        Point2(x + (other.x - x) * t, y + (other.y - y) * t)
    }
}

/// A point or direction in head space.
///
/// Right-handed and viewer-facing: `x` grows to the viewer's right, `y` grows
/// up, and `z` grows *toward* the viewer. The head is modelled as the unit
/// sphere about the origin, so a rotated normal's `z` doubles as a facing test:
/// positive means the surface points at us.
public struct Vec3: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    /// A point on the unit sphere. `lon` sweeps left/right (0 faces the
    /// viewer), `lat` sweeps down/up.
    public static func onSphere(lon: Double, lat: Double, radius: Double = 1) -> Vec3 {
        let cl = cos(lat)
        return Vec3(cl * sin(lon) * radius, sin(lat) * radius, cl * cos(lon) * radius)
    }

    /// Unit vector pointing along increasing longitude at `(lon, lat)`.
    public static func east(lon: Double) -> Vec3 {
        Vec3(cos(lon), 0, -sin(lon))
    }

    /// Unit vector pointing along increasing latitude at `(lon, lat)`.
    public static func north(lon: Double, lat: Double) -> Vec3 {
        Vec3(-sin(lat) * sin(lon), cos(lat), -sin(lat) * cos(lon))
    }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (v: Vec3, k: Double) -> Vec3 { Vec3(v.x * k, v.y * k, v.z * k) }
    public static prefix func - (v: Vec3) -> Vec3 { Vec3(-v.x, -v.y, -v.z) }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public var normalized: Vec3 {
        let l = length
        return l > 1e-12 ? self * (1 / l) : self
    }

    public func dot(_ other: Vec3) -> Double { x * other.x + y * other.y + z * other.z }

    public func lerp(to other: Vec3, _ t: Double) -> Vec3 {
        Vec3(x + (other.x - x) * t, y + (other.y - y) * t, z + (other.z - z) * t)
    }
}

/// A 2D affine transform, laid out like `CGAffineTransform`:
/// `(x, y) -> (a·x + c·y + tx, b·x + d·y + ty)`.
///
/// The rig authors each feature in flat local coordinates and hands it one of
/// these to land it on the rotated head, which is why an eye can be drawn as a
/// plain circle and still arrive squashed and tilted.
public struct Transform2D: Hashable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = Transform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public func apply(_ p: Point2) -> Point2 {
        Point2(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }

    /// Signed area scale. Negative means the frame has flipped away from us.
    public var determinant: Double { a * d - b * c }
}

@inlinable
public func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}

/// Eases `value` from 0 to 1 across `edge0...edge1` with a smooth ramp.
///
/// A descending range (`edge0` above `edge1`) is valid and ramps the other way,
/// which is how the rig asks for "fades in as the eye closes".
@inlinable
public func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    guard edge0 != edge1 else { return value < edge0 ? 0 : 1 }
    let t = clamp((value - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}
