import Foundation

/// Everything that varies frame to frame.
public struct FaceState: Sendable {
    public var pose: Pose
    /// 0 is wide open, 1 is fully shut.
    public var blink: Double
    /// Extra pupil travel, each axis in -1...1, on top of the head turn.
    public var gaze: Point2
    /// Breathing phase in -1...1, driving a small bob.
    public var breath: Double
    /// Draws the construction sphere over the face.
    public var showRig: Bool

    public init(
        pose: Pose = .neutral,
        blink: Double = 0,
        gaze: Point2 = .zero,
        breath: Double = 0,
        showRig: Bool = false
    ) {
        self.pose = pose
        self.blink = blink
        self.gaze = gaze
        self.breath = breath
        self.showRig = showRig
    }
}

/// Proportions and line weights. Every length is a fraction of the head radius,
/// so the face is resolution independent.
public struct CatProportions: Sendable {
    /// Eyes this size, set this close, are most of the character. They crowd
    /// the muzzle down the face, which is why the nose and mouth sit lower here
    /// than anatomy alone would put them.
    public var eyeLongitude = 0.440
    public var eyeLatitude = 0.090
    public var eyeRadius = 0.330
    public var pupilWidth = 0.208
    public var pupilHeight = 0.240
    /// Floats the pupils off the surface. This is what makes them slide across
    /// the iris as the head turns. Perspective means any lift also nudges the
    /// pupil outward at rest, so keep it small enough that the resting eye
    /// still reads as centred.
    public var pupilLift = 0.025

    public var noseLatitude = -0.270
    public var mouthLatitude = -0.400
    public var muzzleLongitude = 0.215
    public var muzzleLatitude = -0.380

    /// The snout, as a sphere sitting in front of the skull.
    ///
    /// This is the difference between a head and a ball with a face painted on
    /// it. Square-on the snout hides inside the head's own outline; on a turn it
    /// breaks the silhouette ahead of the cheek, and a silhouette that changes
    /// shape is the clearest evidence the head is solid.
    public var muzzleForward = 1.00
    public var muzzleDrop = -0.30
    public var muzzleRadius = 0.32
    public var muzzleWidth = 1.15
    /// How far the nose, mouth and whisker pads ride in front of the skull, so
    /// they swing ahead of the face on a turn instead of sliding across it.
    public var muzzleLift = 0.30

    public var outlineWidth = 0.026
    public var featureWidth = 0.030
    public var detailWidth = 0.022
    public var whiskerWidth = 0.018

    public init() {}
}

/// Draws the cat.
///
/// The face is authored as flat vectors, exactly as it would be in a drawing
/// tool. What produces the 3D read is that every one of those vectors is
/// anchored to a longitude/latitude on the head and drawn into the tangent
/// frame there, so turning the head slides, squashes and occludes each feature
/// the way a real one would.
public struct CatRig: Sendable {
    public var head: HeadShape
    public var proportions: CatProportions
    public var canvas: Point2
    public var headCenter: Point2

    public init(
        canvas: Point2 = Point2(520, 700),
        headCenter: Point2 = Point2(260, 255),
        radius: Double = 140,
        proportions: CatProportions = CatProportions()
    ) {
        self.canvas = canvas
        self.headCenter = headCenter
        self.head = HeadShape(radius: radius)
        self.proportions = proportions
    }

    private var radius: Double { head.radius }

    // MARK: - Entry point

    public func draw(_ state: FaceState) -> FaceDrawing {
        // The head rides on a neck, so turning swings it a little rather than
        // spinning it on the spot.
        let bob = state.breath * radius * 0.012
        let center = Point2(
            headCenter.x + sin(state.pose.yaw) * radius * 0.055,
            headCenter.y - sin(state.pose.pitch) * radius * 0.045 + bob
        )
        let projector = Projector(pose: state.pose, head: head, center: center)

        let outlinePoints = headOutlinePoints(projector, state: state)
        let outline = Spline.closedLoop(outlinePoints)
        let snout = snoutSilhouette(projector)
        let rim = weight(proportions.outlineWidth, 1)

        var shapes: [Shape2D] = []
        shapes.append(contentsOf: body(state: state, center: center))

        // The head's shadow on the chest. Painted before the head, so the skull
        // covers its top and what survives is a crescent under the chin — and
        // because it tracks the head's own centre, it slides as the head turns.
        let headBottom = outlinePoints.map(\.y).max() ?? center.y
        var contact = PathBuilder()
        contact.ellipse(
            center: Point2(center.x, headBottom - radius * 0.05),
            rx: radius * 0.52,
            ry: radius * 0.17
        )
        shapes.append(Shape2D(commands: contact.commands, style: .filled(.shadow, opacity: 0.55)))

        let whiskers = whiskerShapes(projector, state: state)
        shapes.append(contentsOf: whiskers.behind)
        shapes.append(contentsOf: crownHairs(projector))
        shapes.append(contentsOf: ears(projector))

        // The snout goes under the head, so the skull's own fill hides the part
        // of it that is inside the outline and only the protruding bump shows.
        // Where the outline crosses the bump, the head's rim reads as the seam
        // between cheek and snout.
        shapes.append(
            Shape2D(commands: snout, style: .outlined(fill: .fur, stroke: .ink, width: rim))
        )
        shapes.append(
            Shape2D(commands: outline, style: .outlined(fill: .fur, stroke: .ink, width: rim))
        )
        if let sheen = rimLight(outlinePoints, center: projector.center) {
            shapes.append(sheen)
        }

        // Everything from here to the whiskers is painted on the head, so it
        // gets cut off at the silhouette rather than floating past it.
        shapes.append(contentsOf: markings(projector).map { $0.clippedToHead() })
        shapes.append(contentsOf: eyes(projector, state: state).map { $0.clippedToHead() })
        shapes.append(contentsOf: muzzle(projector, state: state).map { $0.clippedToHead() })
        shapes.append(contentsOf: whiskers.inFront)

        if state.showRig {
            shapes.append(contentsOf: rigOverlay(projector))
        }

        return FaceDrawing(
            size: canvas,
            shapes: shapes.filter { !$0.isEmpty },
            // Two subpaths, unioned by the non-zero fill rule: the muzzle
            // features ride out past the skull and must not be cut off at it.
            headOutline: outline + snout
        )
    }

    /// Line weights thin out slightly with distance, which reads as depth
    /// without touching the palette.
    private func weight(_ fraction: Double, _ scale: Double) -> Double {
        fraction * radius * (0.86 + 0.14 * scale)
    }

    // MARK: - Head silhouette

    /// Radial profile of the head outline, sampled in the un-rolled screen
    /// frame: 0 is the viewer's right, π/2 is the crown, -π/2 the chin.
    private func headProfile(_ theta: Double, yaw: Double) -> Double {
        var r = 1.0
        r -= 0.055 * window(theta, center: .pi / 2, width: 0.85)   // flat crown between the ears
        r -= 0.050 * window(theta, center: -.pi / 2, width: 0.95)  // jaw tapers in

        // Cheeks. A cat's widest point is below the eyes, not at the equator —
        // putting the bulge there is most of what stops the head reading as a
        // circle. Widening is also the only safe direction: pulling the outline
        // inward would let features off the unit sphere escape it.
        r += 0.130 * window(theta, center: -0.30, width: 1.05)
        r += 0.130 * window(theta, center: .pi + 0.30, width: 1.05)

        // Cheek ruff. Drifting the tufts against the yaw makes the fur read as
        // wrapping around a solid head instead of being painted on a disc.
        let drift = -yaw * 0.20
        r += ruff(theta, center: -0.72 + drift)
        r += ruff(theta, center: .pi + 0.72 + drift)
        return r
    }

    private func window(_ theta: Double, center: Double, width: Double) -> Double {
        let d = wrapAngle(theta - center)
        guard abs(d) < width else { return 0 }
        let w = cos(d / width * .pi / 2)
        return w * w
    }

    private func ruff(_ theta: Double, center: Double, width: Double = 0.66, amp: Double = 0.052) -> Double {
        let d = wrapAngle(theta - center)
        guard abs(d) < width else { return 0 }
        let w = cos(d / width * .pi / 2)
        // A gentle two-lobed ripple inside the window: soft fur, not spikes.
        return amp * w * w * (0.62 + 0.38 * cos(d / width * .pi * 2))
    }

    private func headOutlinePoints(_ projector: Projector, state: FaceState) -> [Point2] {
        let (halfWidth, halfHeight) = projector.silhouette
        // A sphere's silhouette under perspective sits slightly outside its
        // radius; without this the features near the rim crowd the edge.
        let f = head.focalLength
        let bulge = f / max((f * f - 1).squareRoot(), 0.001)

        let samples = 72
        let roll = state.pose.roll
        let cosRoll = cos(roll)
        let sinRoll = sin(roll)

        return (0..<samples).map { i in
            let theta = 2 * .pi * Double(i) / Double(samples)
            let r = headProfile(theta, yaw: state.pose.yaw) * bulge
            let x = halfWidth * r * cos(theta)
            let y = -halfHeight * r * sin(theta)
            return Point2(
                projector.center.x + x * cosRoll - y * sinRoll,
                projector.center.y + x * sinRoll + y * cosRoll
            )
        }
    }

    // MARK: - Snout

    /// The projected outline of the snout sphere.
    ///
    /// A sphere's silhouette under perspective is a circle slightly larger than
    /// its radius would suggest — `a·f / √(D² − a²)` rather than `a·f / D` —
    /// and at this size the difference is visible, so it is worth being exact.
    private func snoutSilhouette(_ projector: Projector) -> [PathCommand] {
        let centre = Vec3(0, proportions.muzzleDrop, proportions.muzzleForward)
        let anchor = projector.project(centre)
        let depth = projector.rotate(centre).z

        let a = proportions.muzzleRadius
        let distance = head.focalLength - depth
        let projected = a * head.focalLength
            / max((distance * distance - a * a).squareRoot(), 0.001)
            * radius

        // Sampled rather than built with `PathBuilder.ellipse`, so it winds the
        // same way as the head outline. The two share a clip path, and under the
        // non-zero fill rule opposite windings would subtract instead of union —
        // punching a hole through the face exactly where the muzzle sits.
        let rx = projected * proportions.muzzleWidth
        let ry = projected
        let samples = 48
        let points = (0..<samples).map { index -> Point2 in
            let theta = 2 * .pi * Double(index) / Double(samples)
            return Point2(
                anchor.position.x + rx * cos(theta),
                anchor.position.y - ry * sin(theta)
            )
        }
        return Spline.closedLoop(points)
    }

    // MARK: - Rim light

    /// A light edge down the lit side of the head.
    ///
    /// Built as a ribbon tapering to nothing at both ends: a stroke cannot fade
    /// along its length, and an arc with hard ends reads as a scratch. The light
    /// sits up and to the left, matching the catchlights in the eyes, so as the
    /// head turns the rim stays put and the silhouette slides under it.
    private func rimLight(_ outline: [Point2], center: Point2) -> Shape2D? {
        guard outline.count > 8 else { return nil }
        let first = Int(Double(outline.count) * 0.21)   // ~75°, just past the crown
        let last = Int(Double(outline.count) * 0.55)    // ~198°, down the far cheek
        guard last > first + 2, last < outline.count else { return nil }

        let arc = Array(outline[first...last])
        let maxWidth = radius * 0.055

        let inner = arc.enumerated().map { index, point -> Point2 in
            let t = Double(index) / Double(arc.count - 1)
            let width = maxWidth * sin(t * .pi)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 1e-9 else { return point }
            let scale = max(length - width, 0) / length
            return Point2(center.x + dx * scale, center.y + dy * scale)
        }

        return Shape2D(
            commands: Spline.closedLoop(arc + inner.reversed()),
            style: .filled(.sheen, opacity: 0.30)
        )
    }

    // MARK: - Ears

    /// The three head-space corners of one ear, plus the direction its opening
    /// faces. Placed directly in 3D rather than by longitude/latitude, because
    /// the base is a ridge that runs diagonally across the skull: inner and
    /// forward at one end, outer and back at the other. That diagonal is what
    /// keeps the ear wide head-on and lets it narrow believably on a turn.
    private func earGeometry(side: Double) -> (front: Vec3, back: Vec3, tip: Vec3, opening: Vec3) {
        // Set well forward on the skull. A base ridge that runs front-to-back
        // sits near the limb, where a turn foreshortens it to nothing and the
        // far ear vanishes; keeping both roots ahead of the equator holds the
        // ear's width right through the turn.
        let frontSurface = Vec3(side * 0.07, 0.94, 0.33).normalized
        let backSurface = Vec3(side * 0.75, 0.56, 0.35).normalized

        // Roots sunk just under the surface so the join is always buried behind
        // the head fill, whatever the pose.
        let front = frontSurface * 0.88
        let back = backSurface * 0.88

        // The tip grows *out of* the base rather than along a scaled radius —
        // scaling a radial vector drags the tip sideways as fast as it lifts it,
        // which is what turns a cat ear into an antler.
        // A taller, more upright ear foreshortens less, so the far one still
        // reads as an ear at the edge of the turn instead of a sliver.
        let baseMid = ((frontSurface + backSurface) * 0.5).normalized
        let tip = baseMid + Vec3(side * 0.11, 0.62, -0.10)

        let opening = Vec3(side * 0.62, 0.30, 0.72).normalized
        return (front, back, tip, opening)
    }

    private func ears(_ projector: Projector) -> [Shape2D] {
        var result: [(depth: Double, shapes: [Shape2D])] = []

        for side in [-1.0, 1.0] {
            let ear = earGeometry(side: side)
            let facing = projector.rotate(ear.opening).z

            var shapes: [Shape2D] = []

            // Outer ear. The front edge dips slightly inward, the back edge
            // bows out — the silhouette a cat ear actually has.
            let frontControl = ear.front.lerp(to: ear.tip, 0.5) + Vec3(-0.04 * side, 0.02, 0.01)
            let backControl = ear.tip.lerp(to: ear.back, 0.5) + Vec3(0.03 * side, -0.02, -0.01)

            var outer = PathBuilder()
            outer.move(projector.project(ear.front).position)
            outer.quad(projector.project(frontControl).position, projector.project(ear.tip).position)
            outer.quad(projector.project(backControl).position, projector.project(ear.back).position)
            outer.close()
            shapes.append(
                Shape2D(
                    commands: outer.commands,
                    style: .outlined(
                        fill: .fur, stroke: .ink,
                        width: weight(proportions.outlineWidth, projector.project(ear.tip).scale)
                    )
                )
            )

            // Inner ear. As the ear turns away this *shrinks* toward the ear's
            // centroid rather than fading: orange at partial opacity over black
            // fur goes muddy brown, which reads as dirt on the ear instead of an
            // ear rotating. Opacity only takes over for the last of it.
            let turn = smoothstep(0.02, 0.44, facing)
            let innerVisibility = min(1, turn * 2.2)
            if turn > 0.02 {
                let centroid = (ear.front + ear.back + ear.tip) * (1.0 / 3.0)
                let shrink = 0.62 * turn
                let lift = ear.opening * 0.05
                let iFront = centroid.lerp(to: ear.front, shrink) + lift
                let iBack = centroid.lerp(to: ear.back, shrink) + lift
                let iTip = centroid.lerp(to: ear.tip, shrink) + lift

                var inner = PathBuilder()
                inner.move(projector.project(iFront).position)
                inner.quad(
                    projector.project(iFront.lerp(to: iTip, 0.5) + Vec3(-0.03 * side, 0, 0)).position,
                    projector.project(iTip).position
                )
                inner.quad(
                    projector.project(iTip.lerp(to: iBack, 0.5) + Vec3(0.04 * side, 0, 0)).position,
                    projector.project(iBack).position
                )
                inner.close()
                shapes.append(
                    Shape2D(
                        commands: inner.commands,
                        style: .filled(.innerEar, opacity: innerVisibility)
                    )
                )
            }

            // Tufts along the ear's front edge. Cheap, and they stop the ear
            // reading as a flat cut-out triangle.
            let centroid = (ear.front + ear.back + ear.tip) * (1.0 / 3.0)
            let tuftVisibility = smoothstep(-0.30, 0.10, facing)
            if tuftVisibility > 0.01 {
                // Roots stay low on the edge. Higher up, "away from the centroid"
                // points straight up and the tuft shoots past the ear tip.
                for (index, t) in [0.16, 0.34, 0.52].enumerated() {
                    let root = ear.front.lerp(to: ear.tip, t)
                    let outward = (root - centroid).normalized
                    let length = [0.085, 0.100, 0.080][index]
                    let tip = root + outward * length + Vec3(0, 0.025, 0)
                    var tuft = PathBuilder()
                    tuft.move(projector.project(root).position)
                    tuft.line(projector.project(tip).position)
                    shapes.append(
                        Shape2D(
                            commands: tuft.commands,
                            style: .stroked(
                                .whisker,
                                width: weight(proportions.whiskerWidth, 1),
                                opacity: tuftVisibility * 0.75
                            )
                        )
                    )
                }
            }

            result.append((projector.rotate(ear.tip).z, shapes))
        }

        // Far ear first, so the near one overlaps it when the head is turned.
        return result.sorted { $0.depth < $1.depth }.flatMap(\.shapes)
    }

    // MARK: - Eyes

    private func eyes(_ projector: Projector, state: FaceState) -> [Shape2D] {
        var shapes: [Shape2D] = []
        let openness = clamp(1 - state.blink, 0, 1)
        let lidMix = smoothstep(0.34, 0.06, openness)
        let eyeR = proportions.eyeRadius * radius
        let pupilW = proportions.pupilWidth * radius
        let pupilH = proportions.pupilHeight * radius

        for side in [-1.0, 1.0] {
            let lon = side * proportions.eyeLongitude
            let lat = proportions.eyeLatitude
            let frame = projector.tangentFrame(lon: lon, lat: lat)
            let visibility = frame.visibility()
            guard visibility > 0.01 else { continue }

            // Shrink the whole eye as it rounds away, not just the width the
            // projection already foreshortens. Left to itself the far eye turns
            // into a tall narrow ellipse pressed against the rim and gets sliced
            // flat by the silhouette — a smear rather than an eye. Taking the
            // height down with the width keeps it inside the outline and reads
            // as an eye that is simply further away.
            let recede = min(1, 0.55 + 0.50 * clamp(frame.facing, 0, 1))
            let eyeR = eyeR * recede
            let pupilW = pupilW * recede
            let pupilH = pupilH * recede

            if openness > 0.02 {
                // No outline: against black fur the amber *is* the eye.
                var iris = PathBuilder()
                iris.ellipse(center: .zero, rx: eyeR, ry: eyeR * openness)
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(iris.commands, by: frame.transform),
                        style: .filled(.iris, opacity: visibility)
                    )
                )

                // The pupil rides a slightly larger sphere, so it drifts against
                // the iris as the head turns — cheap, and the single strongest
                // depth cue on the face.
                let pupilFrame = projector.tangentFrame(
                    lon: lon, lat: lat, lift: proportions.pupilLift
                )
                let gaze = Point2(
                    state.gaze.x * eyeR * 0.20,
                    state.gaze.y * eyeR * 0.16
                )
                var pupil = PathBuilder()
                pupil.ellipse(center: gaze, rx: pupilW, ry: pupilH * openness)
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(pupil.commands, by: pupilFrame.transform),
                        style: .filled(.pupil, opacity: visibility * openness)
                    )
                )

                // Catchlights are offset the same way in both eyes rather than
                // mirrored — they come from one light, up and to the left.
                var glint = PathBuilder()
                let bigR = pupilW * 0.36
                glint.ellipse(
                    center: Point2(gaze.x - pupilW * 0.34, gaze.y - pupilH * 0.40),
                    rx: bigR, ry: bigR * openness
                )
                let smallR = pupilW * 0.11
                glint.ellipse(
                    center: Point2(gaze.x + pupilW * 0.36, gaze.y + pupilH * 0.34),
                    rx: smallR, ry: smallR * openness
                )
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(glint.commands, by: pupilFrame.transform),
                        style: .filled(.glint, opacity: visibility * openness)
                    )
                )
            }

            if lidMix > 0.01 {
                // A shut eye on a black cat would vanish into the coat, so the
                // lid is drawn in the whisker tone: a contented upward arc.
                var lid = PathBuilder()
                lid.move(Point2(-eyeR * 0.85, 0))
                lid.quad(Point2(0, -eyeR * 0.55), Point2(eyeR * 0.85, 0))
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(lid.commands, by: frame.transform),
                        style: .stroked(
                            .whisker,
                            width: weight(proportions.featureWidth, frame.scale),
                            opacity: visibility * lidMix * 0.8
                        )
                    )
                )
            }
        }
        return shapes
    }

    // MARK: - Nose, mouth, muzzle

    private func muzzle(_ projector: Projector, state: FaceState) -> [Shape2D] {
        var shapes: [Shape2D] = []

        // Nose: a soft downward triangle, riding out on the snout.
        let lift = proportions.muzzleLift
        let noseFrame = projector.tangentFrame(
            lon: 0, lat: proportions.noseLatitude, lift: lift
        )
        let noseVisibility = noseFrame.visibility()
        if noseVisibility > 0.01 {
            // A cat's nose is wider than it is tall: a broad, barely domed top
            // and two sides falling to a small rounded tip. Built taller than
            // wide it just reads as a blob.
            // All three corners rounded. A cat's nose is a soft triangle — sharp
            // top corners and a needle tip turn it into a kite.
            let w = 0.088 * radius
            let h = 0.075 * radius
            let top = -h * 0.55
            var nose = PathBuilder()
            nose.move(Point2(-w * 0.72, top))
            nose.quad(Point2(0, top - h * 0.22), Point2(w * 0.72, top))
            nose.cubic(
                Point2(w * 1.02, top + h * 0.10),
                Point2(w * 0.70, h * 0.38),
                Point2(w * 0.26, h * 0.86)
            )
            nose.quad(Point2(0, h * 1.10), Point2(-w * 0.26, h * 0.86))
            nose.cubic(
                Point2(-w * 0.70, h * 0.38),
                Point2(-w * 1.02, top + h * 0.10),
                Point2(-w * 0.72, top)
            )
            nose.close()
            shapes.append(
                Shape2D(
                    commands: PathBuilder.transformed(nose.commands, by: noseFrame.transform),
                    style: .filled(.nose, opacity: noseVisibility)
                )
            )
        }

        // Mouth: the cat's ω, hanging off a short philtrum.
        let mouthFrame = projector.tangentFrame(
            lon: 0, lat: proportions.mouthLatitude, lift: lift * 0.75
        )
        let mouthVisibility = mouthFrame.visibility()
        if mouthVisibility > 0.01 {
            let w = 0.110 * radius
            let d = 0.072 * radius
            // The philtrum is drawn thinner and separately. At the mouth's own
            // weight it fuses with the nose above into one stalk.
            var philtrum = PathBuilder()
            philtrum.move(Point2(0, -0.048 * radius))
            philtrum.line(.zero)
            shapes.append(
                Shape2D(
                    commands: PathBuilder.transformed(philtrum.commands, by: mouthFrame.transform),
                    style: .stroked(
                        .shade,
                        width: weight(proportions.detailWidth * 0.85, mouthFrame.scale),
                        opacity: mouthVisibility * 0.8
                    )
                )
            )

            var mouth = PathBuilder()
            mouth.move(.zero)
            mouth.cubic(Point2(-w * 0.12, d), Point2(-w * 0.82, d), Point2(-w, -d * 0.12))
            mouth.move(.zero)
            mouth.cubic(Point2(w * 0.12, d), Point2(w * 0.82, d), Point2(w, -d * 0.12))
            shapes.append(
                Shape2D(
                    commands: PathBuilder.transformed(mouth.commands, by: mouthFrame.transform),
                    style: .stroked(
                        .shade,
                        width: weight(proportions.featureWidth * 0.88, mouthFrame.scale),
                        opacity: mouthVisibility * 0.9
                    )
                )
            )
        }

        // Whisker pads with their follicle dots.
        for side in [-1.0, 1.0] {
            let frame = projector.tangentFrame(
                lon: side * proportions.muzzleLongitude,
                lat: proportions.muzzleLatitude,
                lift: lift * 0.8
            )
            let visibility = frame.visibility()
            guard visibility > 0.01 else { continue }

            let dotR = 0.0125 * radius
            var dots = PathBuilder()
            for (dx, dy) in [(-0.030, -0.022), (0.014, -0.034), (0.030, 0.004)] {
                dots.ellipse(
                    center: Point2(side * dx * radius, dy * radius),
                    rx: dotR, ry: dotR
                )
            }
            shapes.append(
                Shape2D(commands: dots.commands.map { command in
                    switch command {
                    case .move(let p): return .move(frame.transform.apply(p))
                    case .line(let p): return .line(frame.transform.apply(p))
                    case .quad(let c, let p):
                        return .quad(control: frame.transform.apply(c), to: frame.transform.apply(p))
                    case .cubic(let c1, let c2, let p):
                        return .cubic(
                            control1: frame.transform.apply(c1),
                            control2: frame.transform.apply(c2),
                            to: frame.transform.apply(p)
                        )
                    case .close: return .close
                    }
                }, style: .filled(.shade, opacity: visibility))
            )
        }

        _ = state
        return shapes
    }

    // MARK: - Whiskers

    /// Whiskers are solved fully in 3D rather than drawn into a tangent frame,
    /// because they leave the surface: each one is a root on the head plus a
    /// direction that splays outward and forward.
    private func whiskerShapes(
        _ projector: Projector, state: FaceState
    ) -> (behind: [Shape2D], inFront: [Shape2D]) {
        var behind: [Shape2D] = []
        var inFront: [Shape2D] = []

        // Roots sit on the whisker pads, level with the nose and below — a root
        // any higher sends the top whisker sweeping straight through the eye.
        let layout: [(lat: Double, lonOffset: Double, tilt: Double, length: Double)] = [
            (-0.265, 0.010, 0.22, 0.50),
            (-0.350, 0.000, 0.00, 0.56),
            (-0.435, -0.010, -0.24, 0.48),
        ]

        for side in [-1.0, 1.0] {
            for whisker in layout {
                let lon = side * (0.360 + whisker.lonOffset)
                let lat = whisker.lat
                // Whiskers grow from the pads, which sit on the snout, so their
                // roots ride out in front of the skull with it.
                let root = Vec3.onSphere(lon: lon, lat: lat)
                    * (1 + proportions.muzzleLift * 0.7)
                let east = Vec3.east(lon: lon)
                let north = Vec3.north(lon: lon, lat: lat)

                // Outward along the surface, plus a push off the face so the
                // whisker clears the cheek.
                let direction = (east * side + root * 0.45 + north * whisker.tilt).normalized
                let tip = root + direction * whisker.length
                let droop = Vec3(0, -0.20 * whisker.length, 0)
                let control = root + direction * (whisker.length * 0.55) + droop

                var path = PathBuilder()
                path.move(projector.project(root).position)
                path.quad(
                    projector.project(control).position,
                    projector.project(tip).position
                )

                let rootDepth = projector.rotate(root).z
                let facing = rootDepth  // root sits on the unit sphere, so this is its normal
                let visibility = smoothstep(-0.55, -0.15, facing)
                guard visibility > 0.01 else { continue }

                let shape = Shape2D(
                    commands: path.commands,
                    style: .stroked(
                        .whisker,
                        width: weight(proportions.whiskerWidth, projector.project(root).scale),
                        opacity: visibility * 0.85
                    )
                )

                // A whisker rooted on the far side of the head passes behind it.
                if rootDepth < 0 {
                    behind.append(shape)
                } else {
                    inFront.append(shape)
                }
            }
        }

        _ = state
        return (behind, inFront)
    }

    // MARK: - Markings

    /// Tabby stripes, sampled as arcs across the skull.
    ///
    /// These do more work than anything else on the face: a stripe that wraps
    /// over the crown or slides off the cheek proves the head is a volume, not
    /// a flat badge that happens to be moving.
    private func markings(_ projector: Projector) -> [Shape2D] {
        var shapes: [Shape2D] = []

        func stripe(
            from start: (lon: Double, lat: Double),
            to end: (lon: Double, lat: Double),
            bow: Double = 0,
            paint: Paint = .marking,
            width: Double,
            opacity: Double = 1
        ) {
            let samples = 14
            let points = (0...samples).map { i -> Vec3 in
                let t = Double(i) / Double(samples)
                // A sine bulge bends the stripe without needing extra control
                // points, and it bends *on the sphere*, not on the screen.
                let bulge = sin(t * .pi) * bow
                let lon = start.lon + (end.lon - start.lon) * t
                let lat = start.lat + (end.lat - start.lat) * t + bulge
                return Vec3.onSphere(lon: lon, lat: lat)
            }
            // Fade the whole stripe by how squarely its middle faces us, so one
            // rounding the rim dissolves instead of collapsing into a hard mark
            // pinned to the outline.
            let middle = points[points.count / 2]
            let fade = smoothstep(0.06, 0.34, projector.rotate(middle).z)
            guard fade > 0.01 else { return }

            for run in projector.visibleRuns(points) {
                shapes.append(
                    Shape2D(
                        commands: Spline.openCurve(run),
                        style: .stroked(paint, width: width, opacity: opacity * fade)
                    )
                )
            }
        }

        let detail = weight(proportions.detailWidth, 1)

        // Sheen over the crown. A black cat has no tabby "M" to draw, but the
        // wrap-around cue those stripes provided is worth keeping, so the same
        // arcs survive as light grazing the top of the skull.
        stripe(from: (-0.560, 0.700), to: (-0.260, 0.980), bow: 0.03, width: detail, opacity: 0.30)
        stripe(from: (0.560, 0.700), to: (0.260, 0.980), bow: 0.03, width: detail, opacity: 0.30)

        // Temple and shoulder stripes, wrapping the sides of the skull. They
        // ride near the rim, so they scroll into and out of view on a turn —
        // more convincing than anything drawn on the front of the face.
        for side in [-1.0, 1.0] {
            stripe(
                from: (side * 0.980, 0.520), to: (side * 1.040, 0.180),
                bow: 0.03, width: detail, opacity: 0.55
            )
            // Behind the ear — only ever visible on a hard turn, which is
            // exactly when the illusion needs the payoff.
            stripe(
                from: (side * 1.420, 0.440), to: (side * 1.480, 0.100),
                bow: 0.03, width: detail, opacity: 0.55
            )
        }

        return shapes
    }

    // MARK: - Body

    private func body(state: FaceState, center: Point2) -> [Shape2D] {
        // The body lags the head, so a turn reads as the neck twisting.
        let drift = -sin(state.pose.yaw) * radius * 0.075
        let cx = headCenter.x + drift
        let rim = weight(proportions.outlineWidth, 1)

        let topY = headCenter.y + radius * 0.80 + state.breath * radius * 0.010
        let baseY = canvas.y - radius * 0.32
        let topHalf = radius * 0.48
        let baseHalf = radius * 0.86
        let footY = baseY + radius * 0.14

        var shapes: [Shape2D] = []

        // Tail, drawn first so its root is buried behind the chest and only the
        // part clear of the silhouette reads — the same trick as the ears.
        let sway = state.breath * radius * 0.05
        shapes.append(
            Shape2D(
                commands: taperedShape(
                    from: Point2(cx + baseHalf * 0.60, baseY - radius * 0.46),
                    control: Point2(cx + baseHalf * 1.78, baseY - radius * 0.06 + sway),
                    to: Point2(cx + baseHalf * 1.52, baseY - radius * 0.98 + sway),
                    startHalfWidth: radius * 0.150,
                    endHalfWidth: radius * 0.090
                ),
                style: .outlined(fill: .fur, stroke: .ink, width: rim)
            )
        )

        // Chest: narrow at the shoulders, flaring to a broad seated base.
        var chest = PathBuilder()
        chest.move(Point2(cx - topHalf, topY))
        chest.cubic(
            Point2(cx - topHalf - radius * 0.14, topY + radius * 0.60),
            Point2(cx - baseHalf, baseY - radius * 0.70),
            Point2(cx - baseHalf, baseY - radius * 0.16)
        )
        chest.cubic(
            Point2(cx - baseHalf, footY),
            Point2(cx - baseHalf * 0.74, footY),
            Point2(cx - baseHalf * 0.48, footY)
        )
        chest.line(Point2(cx + baseHalf * 0.48, footY))
        chest.cubic(
            Point2(cx + baseHalf * 0.74, footY),
            Point2(cx + baseHalf, footY),
            Point2(cx + baseHalf, baseY - radius * 0.16)
        )
        chest.cubic(
            Point2(cx + baseHalf, baseY - radius * 0.70),
            Point2(cx + topHalf + radius * 0.14, topY + radius * 0.60),
            Point2(cx + topHalf, topY)
        )
        chest.close()
        shapes.append(
            Shape2D(commands: chest.commands, style: .outlined(fill: .fur, stroke: .ink, width: rim))
        )

        // Front paws only. On a seated cat the legs are swallowed by the chest,
        // and drawing them as columns just reads as two rectangles stuck on.
        let pawHalfWidth = radius * 0.215
        let pawHalfHeight = radius * 0.135
        let pawY = footY - radius * 0.115
        for side in [-1.0, 1.0] {
            let px = cx + side * radius * 0.285
            var paw = PathBuilder()
            paw.ellipse(center: Point2(px, pawY), rx: pawHalfWidth, ry: pawHalfHeight)
            shapes.append(
                Shape2D(commands: paw.commands, style: .outlined(fill: .fur, stroke: .ink, width: rim))
            )

            var toes = PathBuilder()
            for toe in [-0.36, 0.36] {
                toes.move(Point2(px + pawHalfWidth * toe, pawY - pawHalfHeight * 0.10))
                toes.line(Point2(px + pawHalfWidth * toe, pawY + pawHalfHeight * 0.74))
            }
            shapes.append(
                Shape2D(
                    commands: toes.commands,
                    style: .stroked(.ink, width: weight(proportions.detailWidth, 1), opacity: 0.85)
                )
            )
        }

        return shapes
    }

    /// Outlines a quadratic spine whose width tapers along its length.
    ///
    /// The tail needs a fill and a rim like every other part of the cat, so it
    /// cannot simply be a stroked line.
    private func taperedShape(
        from start: Point2,
        control: Point2,
        to end: Point2,
        startHalfWidth: Double,
        endHalfWidth: Double,
        samples: Int = 18
    ) -> [PathCommand] {
        var near: [Point2] = []
        var far: [Point2] = []

        for index in 0...samples {
            let t = Double(index) / Double(samples)
            let mt = 1 - t
            let point = Point2(
                mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x,
                mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
            )
            let tangent = Point2(
                2 * mt * (control.x - start.x) + 2 * t * (end.x - control.x),
                2 * mt * (control.y - start.y) + 2 * t * (end.y - control.y)
            )
            let length = (tangent.x * tangent.x + tangent.y * tangent.y).squareRoot()
            guard length > 1e-9 else { continue }
            let normal = Point2(-tangent.y / length, tangent.x / length)
            let halfWidth = startHalfWidth + (endHalfWidth - startHalfWidth) * t
            near.append(Point2(point.x + normal.x * halfWidth, point.y + normal.y * halfWidth))
            far.append(Point2(point.x - normal.x * halfWidth, point.y - normal.y * halfWidth))
        }

        return Spline.closedLoop(near + far.reversed())
    }

    // MARK: - Stray hairs

    /// A few wisps off the crown, between the ears.
    ///
    /// Drawn behind the head like the ears, so their roots are buried and only
    /// the part clearing the skull shows.
    private func crownHairs(_ projector: Projector) -> [Shape2D] {
        // Short, splayed and curved. Straight parallel hairs read as antennae.
        let layout: [(lon: Double, lat: Double, lean: Double, length: Double)] = [
            (-0.130, 1.320, -0.520, 0.105),
            (-0.010, 1.390, -0.120, 0.130),
            (0.115, 1.330, 0.420, 0.110),
        ]

        return layout.compactMap { hair in
            let root = Vec3.onSphere(lon: hair.lon, lat: hair.lat)
            let direction = (root + Vec3(hair.lean, 0.70, 0)).normalized
            let tip = root + direction * hair.length
            let control = root + direction * (hair.length * 0.55)
                + Vec3(hair.lean * 0.10, -0.012, 0)

            let visibility = smoothstep(-0.40, 0.05, projector.rotate(root).z)
            guard visibility > 0.01 else { return nil }

            var path = PathBuilder()
            path.move(projector.project(root).position)
            path.quad(
                projector.project(control).position,
                projector.project(tip).position
            )
            return Shape2D(
                commands: path.commands,
                style: .stroked(
                    .whisker,
                    width: weight(proportions.whiskerWidth, 1),
                    opacity: visibility * 0.6
                )
            )
        }
    }

    // MARK: - Rig overlay

    /// The construction sphere, exposed on demand. It is the answer to "how is
    /// this even possible" — the face is flat, the scaffolding is not.
    private func rigOverlay(_ projector: Projector) -> [Shape2D] {
        var shapes: [Shape2D] = []
        let hairline = radius * 0.010
        let dash = [radius * 0.035, radius * 0.045]

        // Parallels.
        for step in stride(from: -60.0, through: 60.0, by: 30.0) {
            let lat = step * .pi / 180
            let points = stride(from: -180.0, through: 180.0, by: 4.0).map { degrees in
                Vec3.onSphere(lon: degrees * .pi / 180, lat: lat)
            }
            for run in projector.visibleRuns(points, threshold: 0.01) {
                shapes.append(
                    Shape2D(
                        commands: Spline.openCurve(run),
                        style: .stroked(.guide, width: hairline, opacity: 0.55, dash: dash)
                    )
                )
            }
        }

        // Meridians.
        for step in stride(from: -180.0, to: 180.0, by: 30.0) {
            let lon = step * .pi / 180
            let points = stride(from: -85.0, through: 85.0, by: 4.0).map { degrees in
                Vec3.onSphere(lon: lon, lat: degrees * .pi / 180)
            }
            for run in projector.visibleRuns(points, threshold: 0.01) {
                shapes.append(
                    Shape2D(
                        commands: Spline.openCurve(run),
                        style: .stroked(.guide, width: hairline, opacity: 0.55, dash: dash)
                    )
                )
            }
        }

        // Anchor points, with the local axes drawn at the eyes.
        let anchors: [(Double, Double)] = [
            (proportions.eyeLongitude, proportions.eyeLatitude),
            (-proportions.eyeLongitude, proportions.eyeLatitude),
            (0, proportions.noseLatitude),
            (0, proportions.mouthLatitude),
            (proportions.muzzleLongitude, proportions.muzzleLatitude),
            (-proportions.muzzleLongitude, proportions.muzzleLatitude),
        ]
        for (lon, lat) in anchors {
            let frame = projector.tangentFrame(lon: lon, lat: lat)
            guard frame.facing > 0 else { continue }
            var dot = PathBuilder()
            let r = radius * 0.016
            dot.ellipse(center: frame.origin, rx: r, ry: r)
            shapes.append(Shape2D(commands: dot.commands, style: .filled(.guide, opacity: 0.9)))

            let axis = radius * 0.13
            var cross = PathBuilder()
            cross.move(frame.transform.apply(Point2(-axis, 0)))
            cross.line(frame.transform.apply(Point2(axis, 0)))
            cross.move(frame.transform.apply(Point2(0, -axis)))
            cross.line(frame.transform.apply(Point2(0, axis)))
            shapes.append(
                Shape2D(commands: cross.commands, style: .stroked(.guide, width: hairline, opacity: 0.8))
            )
        }

        return shapes
    }
}

@inlinable
func wrapAngle(_ angle: Double) -> Double {
    var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi }
    if a < -.pi { a += 2 * .pi }
    return a
}
