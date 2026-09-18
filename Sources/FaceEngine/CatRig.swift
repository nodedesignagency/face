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
    public var eyeLongitude = 0.455
    public var eyeLatitude = 0.045
    public var eyeRadius = 0.195
    public var pupilRadius = 0.105
    /// Floats the pupils off the surface. This is what makes them slide across
    /// the eye whites as the head turns. Perspective means any lift also nudges
    /// the pupil outward at rest, so keep it small enough that the resting eye
    /// still reads as centred.
    public var pupilLift = 0.025

    public var noseLatitude = -0.215
    public var mouthLatitude = -0.330
    public var muzzleLongitude = 0.215
    public var muzzleLatitude = -0.300

    public var outlineWidth = 0.052
    public var featureWidth = 0.042
    public var detailWidth = 0.026
    public var whiskerWidth = 0.021

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
        canvas: Point2 = Point2(520, 620),
        headCenter: Point2 = Point2(260, 255),
        radius: Double = 162,
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

        let outline = Spline.closedLoop(headOutlinePoints(projector, state: state))

        var shapes: [Shape2D] = []
        shapes.append(contentsOf: body(state: state, center: center))

        let whiskers = whiskerShapes(projector, state: state)
        shapes.append(contentsOf: whiskers.behind)
        shapes.append(contentsOf: ears(projector))
        shapes.append(
            Shape2D(
                commands: outline,
                style: .outlined(
                    fill: .paper, stroke: .ink, width: weight(proportions.outlineWidth, 1)
                )
            )
        )
        // Everything from here to the whiskers is painted on the skull, so it
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
            headOutline: outline
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
        r -= 0.020 * window(theta, center: .pi / 2, width: 0.95)   // flatter crown
        r -= 0.045 * window(theta, center: -.pi / 2, width: 1.05)  // narrower chin

        // Broad cheeks. Widening the sides rather than squashing the crown is
        // what keeps every feature inside the outline.
        r += 0.045 * window(theta, center: 0, width: 0.95)
        r += 0.045 * window(theta, center: .pi, width: 0.95)

        // Cheek ruff. Drifting the tufts against the yaw makes the fur read as
        // wrapping around a solid head instead of being painted on a disc.
        let drift = -yaw * 0.20
        r += ruff(theta, center: -0.62 + drift)
        r += ruff(theta, center: .pi + 0.62 + drift)
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
                        fill: .paper, stroke: .ink,
                        width: weight(proportions.outlineWidth, projector.project(ear.tip).scale)
                    )
                )
            )

            // Inner ear, shrunk toward the ear's centroid and lifted out of the
            // ear plane so it disappears as the ear turns away.
            let innerVisibility = smoothstep(-0.05, 0.34, facing)
            if innerVisibility > 0.01 {
                let centroid = (ear.front + ear.back + ear.tip) * (1.0 / 3.0)
                let shrink = 0.56
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
                    Shape2D(commands: inner.commands, style: .filled(.blush, opacity: innerVisibility))
                )
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
        let pupilR = proportions.pupilRadius * radius

        for side in [-1.0, 1.0] {
            let lon = side * proportions.eyeLongitude
            let lat = proportions.eyeLatitude
            let frame = projector.tangentFrame(lon: lon, lat: lat)
            let visibility = frame.visibility()
            guard visibility > 0.01 else { continue }

            if openness > 0.02 {
                var eye = PathBuilder()
                eye.ellipse(center: .zero, rx: eyeR, ry: eyeR * openness)
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(eye.commands, by: frame.transform),
                        style: .outlined(
                            fill: .paper, stroke: .ink,
                            width: weight(proportions.featureWidth, frame.scale),
                            opacity: visibility
                        )
                    )
                )

                // The pupil rides a slightly larger sphere, so it drifts against
                // the eye white as the head turns — cheap, and it is the single
                // strongest depth cue on the face.
                let pupilFrame = projector.tangentFrame(
                    lon: lon, lat: lat, lift: proportions.pupilLift
                )
                let gaze = Point2(
                    state.gaze.x * eyeR * 0.26,
                    state.gaze.y * eyeR * 0.22
                )
                var pupil = PathBuilder()
                pupil.ellipse(center: gaze, rx: pupilR, ry: pupilR * openness)
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(pupil.commands, by: pupilFrame.transform),
                        style: .filled(.ink, opacity: visibility * openness)
                    )
                )

                var glint = PathBuilder()
                let glintR = pupilR * 0.30
                glint.ellipse(
                    center: Point2(gaze.x - pupilR * 0.26, gaze.y - pupilR * 0.28),
                    rx: glintR, ry: glintR * openness
                )
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(glint.commands, by: pupilFrame.transform),
                        style: .filled(.paper, opacity: visibility * openness)
                    )
                )
            }

            if lidMix > 0.01 {
                // A closed cat eye is a contented upward arc, not a flat line.
                var lid = PathBuilder()
                lid.move(Point2(-eyeR, 0))
                lid.quad(Point2(0, -eyeR * 0.62), Point2(eyeR, 0))
                shapes.append(
                    Shape2D(
                        commands: PathBuilder.transformed(lid.commands, by: frame.transform),
                        style: .stroked(
                            .ink,
                            width: weight(proportions.featureWidth, frame.scale),
                            opacity: visibility * lidMix
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

        // Nose: a soft downward triangle.
        let noseFrame = projector.tangentFrame(lon: 0, lat: proportions.noseLatitude)
        let noseVisibility = noseFrame.visibility()
        if noseVisibility > 0.01 {
            let w = 0.088 * radius
            let h = 0.068 * radius
            var nose = PathBuilder()
            nose.move(Point2(-w, -h * 0.5))
            nose.quad(Point2(0, -h * 1.15), Point2(w, -h * 0.5))
            nose.quad(Point2(w * 0.72, h * 0.42), Point2(0, h))
            nose.quad(Point2(-w * 0.72, h * 0.42), Point2(-w, -h * 0.5))
            nose.close()
            shapes.append(
                Shape2D(
                    commands: PathBuilder.transformed(nose.commands, by: noseFrame.transform),
                    style: .outlined(
                        fill: .blush, stroke: .ink,
                        width: weight(proportions.detailWidth, noseFrame.scale),
                        opacity: noseVisibility
                    )
                )
            )
        }

        // Mouth: the cat's ω, hanging off a short philtrum.
        let mouthFrame = projector.tangentFrame(lon: 0, lat: proportions.mouthLatitude)
        let mouthVisibility = mouthFrame.visibility()
        if mouthVisibility > 0.01 {
            let w = 0.125 * radius
            let d = 0.082 * radius
            var mouth = PathBuilder()
            mouth.move(Point2(0, -0.055 * radius))
            mouth.line(.zero)
            mouth.move(.zero)
            mouth.cubic(Point2(-w * 0.12, d), Point2(-w * 0.82, d), Point2(-w, -d * 0.12))
            mouth.move(.zero)
            mouth.cubic(Point2(w * 0.12, d), Point2(w * 0.82, d), Point2(w, -d * 0.12))
            shapes.append(
                Shape2D(
                    commands: PathBuilder.transformed(mouth.commands, by: mouthFrame.transform),
                    style: .stroked(
                        .ink,
                        width: weight(proportions.featureWidth, mouthFrame.scale),
                        opacity: mouthVisibility
                    )
                )
            )
        }

        // Whisker pads with their follicle dots.
        for side in [-1.0, 1.0] {
            let frame = projector.tangentFrame(
                lon: side * proportions.muzzleLongitude,
                lat: proportions.muzzleLatitude
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
                let root = Vec3.onSphere(lon: lon, lat: lat)
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
                        .ink,
                        width: weight(proportions.whiskerWidth, projector.project(root).scale),
                        opacity: visibility * 0.9
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

        // Forehead: the tabby "M".
        stripe(from: (-0.330, 0.380), to: (-0.145, 0.760), bow: 0.03, width: detail)
        stripe(from: (0.000, 0.430), to: (0.000, 0.820), width: detail)
        stripe(from: (0.330, 0.380), to: (0.145, 0.760), bow: 0.03, width: detail)

        // Temple and shoulder stripes, wrapping the sides of the skull. They
        // ride near the rim, so they scroll into and out of view on a turn —
        // more convincing than anything drawn on the front of the face.
        for side in [-1.0, 1.0] {
            stripe(
                from: (side * 0.950, 0.540), to: (side * 1.010, 0.160),
                bow: 0.03, width: detail
            )
            stripe(
                from: (side * 1.220, 0.480), to: (side * 1.280, 0.100),
                bow: 0.03, width: detail
            )
            // Behind the ear — only ever visible on a hard turn, which is
            // exactly when the illusion needs the payoff.
            stripe(
                from: (side * 1.490, 0.420), to: (side * 1.550, 0.060),
                bow: 0.03, width: detail
            )
        }

        return shapes
    }

    // MARK: - Body

    private func body(state: FaceState, center: Point2) -> [Shape2D] {
        // The body lags the head, so a turn reads as the neck twisting.
        let drift = -sin(state.pose.yaw) * radius * 0.075
        let cx = headCenter.x + drift
        let shoulderY = headCenter.y + radius * 0.98 + state.breath * radius * 0.008
        let halfWidth = radius * 1.05
        let neckHalf = radius * 0.34
        let bottom = canvas.y + radius * 0.2

        var path = PathBuilder()
        path.move(Point2(cx - halfWidth, bottom))
        path.line(Point2(cx - halfWidth, shoulderY + radius * 0.34))
        path.cubic(
            Point2(cx - halfWidth, shoulderY + radius * 0.02),
            Point2(cx - neckHalf - radius * 0.24, shoulderY - radius * 0.20),
            Point2(cx - neckHalf, shoulderY - radius * 0.30)
        )
        path.line(Point2(cx + neckHalf, shoulderY - radius * 0.30))
        path.cubic(
            Point2(cx + neckHalf + radius * 0.24, shoulderY - radius * 0.20),
            Point2(cx + halfWidth, shoulderY + radius * 0.02),
            Point2(cx + halfWidth, shoulderY + radius * 0.34)
        )
        path.line(Point2(cx + halfWidth, bottom))
        path.close()

        var shapes = [
            Shape2D(
                commands: path.commands,
                style: .outlined(
                    fill: .paper, stroke: .ink, width: weight(proportions.outlineWidth, 1)
                )
            )
        ]

        // Collar, bowed to sit on a round neck rather than a flat one.
        let collarY = shoulderY + radius * 0.14
        let collarHalf = neckHalf + radius * 0.13
        var collar = PathBuilder()
        collar.move(Point2(cx - collarHalf, collarY - radius * 0.045))
        collar.quad(Point2(cx, collarY + radius * 0.075), Point2(cx + collarHalf, collarY - radius * 0.045))
        shapes.append(
            Shape2D(
                commands: collar.commands,
                style: .stroked(.accent, width: radius * 0.075, cap: .round)
            )
        )

        var tag = PathBuilder()
        let tagR = radius * 0.072
        tag.ellipse(center: Point2(cx, collarY + radius * 0.115), rx: tagR, ry: tagR)
        shapes.append(
            Shape2D(
                commands: tag.commands,
                style: .outlined(
                    fill: .accent, stroke: .ink, width: weight(proportions.detailWidth, 1)
                )
            )
        )

        return shapes
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
