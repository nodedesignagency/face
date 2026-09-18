import Foundation

/// How far the head is allowed to turn.
public struct PoseLimits: Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(yaw: Double = 0.72, pitch: Double = 0.40, roll: Double = 0.15) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public static let `default` = PoseLimits()
}

/// Drives the face over time: springs the head toward whatever it is tracking,
/// wanders when nothing is, blinks, and breathes.
///
/// Deliberately a plain value type with an explicit `advance(to:)` — no timers,
/// no framework — so the whole behaviour is testable without rendering a frame.
public struct FaceAnimator: Sendable {
    public var limits: PoseLimits
    /// Rest angular frequency of the head spring, in radians per second.
    public var stiffness: Double = 11.0
    /// 1 is critically damped. A little under gives the head a soft overshoot.
    public var dampingRatio: Double = 0.82
    /// Seconds of no input before the cat starts looking around by itself.
    public var idleDelay: Double = 2.4

    public private(set) var pose: Pose = .neutral
    public private(set) var blink: Double = 0
    public private(set) var gaze: Point2 = .zero

    private var velocity = Pose()
    private var aim = Point2.zero
    private var isTracking = false
    private var lastInputTime: Double = -1000
    private var lastTime: Double?
    private var blinkStart: Double?
    private var nextBlinkTime: Double
    private var pendingDoubleBlink = false
    private var random: SplitMix64

    public init(seed: UInt64 = 0x5EED_CA7) {
        self.limits = .default
        self.random = SplitMix64(seed: seed)
        self.nextBlinkTime = 1.6
    }

    /// Current frame, ready to hand to the rig.
    public func state(at time: Double, showRig: Bool = false) -> FaceState {
        FaceState(
            pose: pose,
            blink: blink,
            gaze: gaze,
            breath: sin(time * 1.15),
            showRig: showRig
        )
    }

    /// Points the head at a spot in normalized -1...1 coordinates, where
    /// (0, 0) is straight ahead and +y is below centre.
    public mutating func look(at point: Point2, time: Double) {
        aim = Point2(clamp(point.x, -1, 1), clamp(point.y, -1, 1))
        isTracking = true
        lastInputTime = time
    }

    /// Hands control back to the idle wander.
    public mutating func releaseTracking(time: Double) {
        isTracking = false
        lastInputTime = time
    }

    public mutating func advance(to time: Double) {
        let previous = lastTime ?? time
        lastTime = time
        // Clamp so a backgrounded app or a debugger pause cannot fling the head.
        var remaining = clamp(time - previous, 0, 0.25)

        let target = targetPose(at: time)

        // Fixed substeps keep the spring stable regardless of frame rate.
        let maxStep = 1.0 / 120.0
        while remaining > 0 {
            let dt = min(remaining, maxStep)
            remaining -= dt
            integrate(toward: target, dt: dt)
        }

        updateBlink(at: time)
        updateGaze()
    }

    // MARK: - Internals

    private func targetPose(at time: Double) -> Pose {
        let tracked = Pose(
            yaw: aim.x * limits.yaw,
            pitch: -aim.y * limits.pitch,
            // The head tilts into the turn; cats lead with the skull, not the neck.
            roll: -aim.x * limits.roll * 0.65
        )

        let idleAmount = isTracking
            ? 0
            : smoothstep(idleDelay, idleDelay + 1.4, time - lastInputTime)
        guard idleAmount > 0.001 else { return tracked }

        let wanderYaw = 0.46 * sin(time * 0.31) + 0.18 * sin(time * 0.73 + 1.3)
        let wanderPitch = 0.34 * sin(time * 0.41 + 0.7) + 0.13 * sin(time * 0.97 + 2.4)
        let wanderRoll = 0.40 * sin(time * 0.23 + 2.1)
        let idle = Pose(
            yaw: wanderYaw * limits.yaw * 0.72,
            pitch: wanderPitch * limits.pitch * 0.66,
            roll: wanderRoll * limits.roll * 0.8
        )
        return tracked.lerp(to: idle, idleAmount)
    }

    private mutating func integrate(toward target: Pose, dt: Double) {
        let k = stiffness * stiffness
        let c = 2 * dampingRatio * stiffness

        func step(_ value: Double, _ velocity: Double, _ goal: Double) -> (Double, Double) {
            let acceleration = k * (goal - value) - c * velocity
            let newVelocity = velocity + acceleration * dt
            return (value + newVelocity * dt, newVelocity)
        }

        let (yaw, yawV) = step(pose.yaw, velocity.yaw, target.yaw)
        let (pitch, pitchV) = step(pose.pitch, velocity.pitch, target.pitch)
        let (roll, rollV) = step(pose.roll, velocity.roll, target.roll)

        pose = Pose(yaw: yaw, pitch: pitch, roll: roll)
        velocity = Pose(yaw: yawV, pitch: pitchV, roll: rollV)
    }

    private mutating func updateGaze() {
        // Once the head hits its limit the eyes carry the rest of the look.
        let headShare = Point2(pose.yaw / limits.yaw, -pose.pitch / limits.pitch)
        let residual = Point2(aim.x - headShare.x, aim.y - headShare.y)
        gaze = Point2(clamp(residual.x * 1.4, -1, 1), clamp(residual.y * 1.4, -1, 1))
    }

    private static let closeDuration = 0.085
    private static let holdDuration = 0.045
    private static let openDuration = 0.150
    private static var blinkDuration: Double { closeDuration + holdDuration + openDuration }

    private mutating func updateBlink(at time: Double) {
        if blinkStart == nil, time >= nextBlinkTime {
            blinkStart = time
        }

        guard let start = blinkStart else {
            blink = 0
            return
        }

        let elapsed = time - start
        if elapsed >= Self.blinkDuration {
            blinkStart = nil
            blink = 0
            if pendingDoubleBlink {
                pendingDoubleBlink = false
                nextBlinkTime = time + 0.14
            } else {
                // Cats blink slowly and irregularly; a flat interval reads as a
                // machine rather than an animal.
                pendingDoubleBlink = random.nextUnit() < 0.22
                nextBlinkTime = time + 2.4 + random.nextUnit() * 4.2
            }
            return
        }

        if elapsed < Self.closeDuration {
            blink = smoothstep(0, Self.closeDuration, elapsed)
        } else if elapsed < Self.closeDuration + Self.holdDuration {
            blink = 1
        } else {
            let t = elapsed - Self.closeDuration - Self.holdDuration
            blink = 1 - smoothstep(0, Self.openDuration, t)
        }
    }
}

/// Small seeded generator so blink timing is repeatable in tests.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
