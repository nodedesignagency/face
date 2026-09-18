import Foundation

/// How far the head is turned, in radians.
public struct Pose: Hashable, Sendable {
    /// Positive turns the head toward the viewer's right.
    public var yaw: Double
    /// Positive lifts the muzzle.
    public var pitch: Double
    /// Head tilt, the "curious cat" axis.
    public var roll: Double

    public init(yaw: Double = 0, pitch: Double = 0, roll: Double = 0) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public static let neutral = Pose()

    public func lerp(to other: Pose, _ t: Double) -> Pose {
        Pose(
            yaw: yaw + (other.yaw - yaw) * t,
            pitch: pitch + (other.pitch - pitch) * t,
            roll: roll + (other.roll - roll) * t
        )
    }
}

/// The result of flattening a head-space point onto the canvas.
public struct Projected: Hashable, Sendable {
    public var position: Point2
    /// Perspective multiplier at this depth — above 1 when closer than the origin.
    public var scale: Double
    /// Rotated `z`. Positive is toward the viewer.
    public var depth: Double
}

/// A flat drawing surface glued to one spot on the head.
public struct TangentFrame: Hashable, Sendable {
    /// Maps local canvas points (already in canvas units) onto the head.
    public var transform: Transform2D
    /// Rotated surface normal's `z`: 1 aimed straight at us, 0 at the silhouette
    /// edge, negative around the back.
    public var facing: Double
    public var depth: Double
    public var scale: Double
    public var origin: Point2

    /// Opacity ramp that fades a feature out as it rounds the silhouette,
    /// rather than letting it pop.
    public func visibility(from: Double = 0.02, to: Double = 0.26) -> Double {
        smoothstep(from, to, facing)
    }
}

/// The head as a slightly squashed ellipsoid, in units of `radius`.
///
/// Features are anchored to the *unit sphere*, so an axis below 1 pulls the
/// outline inside the surface those features sit on and they escape the head —
/// the ear roots are the first to go. Keep width and height at 1 and shape the
/// head with `CatRig`'s radial profile instead, which can only push the outline
/// outward. `depthAxis` is the exception: it only ever shrinks the silhouette on
/// a turn, and the pose limits keep that well clear of the front features.
public struct HeadShape: Hashable, Sendable {
    /// Half-width of the front-facing head, in canvas units.
    public var radius: Double
    public var widthAxis: Double
    public var heightAxis: Double
    public var depthAxis: Double
    /// Distance from the eye to the projection plane, in radius units. Smaller
    /// exaggerates the bulge.
    public var focalLength: Double

    public init(
        radius: Double,
        widthAxis: Double = 1.0,
        heightAxis: Double = 1.0,
        depthAxis: Double = 0.95,
        focalLength: Double = 3.1
    ) {
        self.radius = radius
        self.widthAxis = widthAxis
        self.heightAxis = heightAxis
        self.depthAxis = depthAxis
        self.focalLength = focalLength
    }
}

/// Turns head-space geometry into canvas geometry for one pose.
///
/// Everything the rig draws goes through here, which is the whole trick: the
/// features are flat vectors, but their *anchors* live on a sphere, so rotating
/// the sphere slides them across the face with correct foreshortening.
public struct Projector: Sendable {
    public let pose: Pose
    public let head: HeadShape
    public let center: Point2

    private let cosYaw: Double
    private let sinYaw: Double
    private let cosPitch: Double
    private let sinPitch: Double
    private let cosRoll: Double
    private let sinRoll: Double

    public init(pose: Pose, head: HeadShape, center: Point2) {
        self.pose = pose
        self.head = head
        self.center = center
        self.cosYaw = cos(pose.yaw)
        self.sinYaw = sin(pose.yaw)
        self.cosPitch = cos(pose.pitch)
        self.sinPitch = sin(pose.pitch)
        self.cosRoll = cos(pose.roll)
        self.sinRoll = sin(pose.roll)
    }

    /// Yaw about Y, then pitch about X, then roll about Z.
    ///
    /// Pitch runs so that a positive angle tips the muzzle *up*, matching how
    /// `Pose` documents it and how the animator maps a pointer above centre.
    public func rotate(_ v: Vec3) -> Vec3 {
        let x1 = v.x * cosYaw + v.z * sinYaw
        let z1 = -v.x * sinYaw + v.z * cosYaw
        let y1 = v.y

        let y2 = y1 * cosPitch + z1 * sinPitch
        let z2 = -y1 * sinPitch + z1 * cosPitch

        return Vec3(x1 * cosRoll - y2 * sinRoll, x1 * sinRoll + y2 * cosRoll, z2)
    }

    public func project(_ v: Vec3) -> Projected {
        let r = rotate(v)
        // Guard against a point crossing the eye when focalLength is small.
        let scale = head.focalLength / max(head.focalLength - r.z, 0.2)
        return Projected(
            position: Point2(
                center.x + r.x * scale * head.radius,
                center.y - r.y * scale * head.radius
            ),
            scale: scale,
            depth: r.z
        )
    }

    /// Builds the local drawing surface at `(lon, lat)`.
    ///
    /// `lift` floats the frame above the surface. Giving the pupils a little
    /// lift is what makes them parallax against the eye whites when the head
    /// turns, which sells the depth more than any amount of shading.
    public func tangentFrame(lon: Double, lat: Double, lift: Double = 0) -> TangentFrame {
        let normal = Vec3.onSphere(lon: lon, lat: lat)
        let anchor = project(normal * (1 + lift))

        let east = rotate(Vec3.east(lon: lon))
        let north = rotate(Vec3.north(lon: lon, lat: lat))
        let rotatedNormal = rotate(normal)
        let s = anchor.scale

        // Local +x follows east; local +y points down, so it follows -north.
        let transform = Transform2D(
            a: east.x * s, b: -east.y * s,
            c: -north.x * s, d: north.y * s,
            tx: anchor.position.x, ty: anchor.position.y
        )

        return TangentFrame(
            transform: transform,
            facing: rotatedNormal.z,
            depth: anchor.depth,
            scale: s,
            origin: anchor.position
        )
    }

    /// How far the head's outline reaches, in canvas units.
    ///
    /// An ellipsoid's silhouette stays an ellipse under rotation, and its
    /// half-extent along each axis interpolates between the two axes it sweeps
    /// between. Near-spherical axes keep this subtle — the head reads as solid
    /// without visibly deforming.
    public var silhouette: (halfWidth: Double, halfHeight: Double) {
        let w = ((head.widthAxis * cosYaw) * (head.widthAxis * cosYaw)
            + (head.depthAxis * sinYaw) * (head.depthAxis * sinYaw)).squareRoot()
        let h = ((head.heightAxis * cosPitch) * (head.heightAxis * cosPitch)
            + (head.depthAxis * sinPitch) * (head.depthAxis * sinPitch)).squareRoot()
        return (w * head.radius, h * head.radius)
    }

    /// Projects a run of head-space points, splitting it wherever it rounds out
    /// of sight so a stripe wrapping the head doesn't smear across the face.
    public func visibleRuns(
        _ points: [Vec3],
        threshold: Double = 0.04
    ) -> [[Point2]] {
        var runs: [[Point2]] = []
        var current: [Point2] = []

        for point in points {
            let rotated = rotate(point)
            // Facing is measured against the point's own normal, which for a
            // point on the unit sphere is the point itself.
            if rotated.z > threshold * point.length {
                current.append(project(point).position)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs.filter { $0.count > 1 }
    }
}
