#if canImport(SwiftUI)
import FaceEngine
import Foundation

#if canImport(CoreMotion) && os(iOS)
import CoreMotion

/// Turns device tilt into an aim point in -1...1.
///
/// The attitude held when tracking starts becomes the neutral pose, so it works
/// the same lying in bed as sitting at a desk instead of assuming the phone is
/// upright.
///
/// Updates are delivered to `OperationQueue.main` and only ever read from the
/// main thread, so this stays free of isolation annotations that would rule out
/// the iOS 16 deployment target.
public final class MotionSource {
    public private(set) var aim: Point2?
    public var isAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Tilt, in radians, that maps to a full turn of the head.
    public var travel: Double = 0.55

    private let manager = CMMotionManager()
    private var reference: CMAttitude?

    public init() {}

    public func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        reference = nil
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.ingest(motion.attitude)
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
        aim = nil
    }

    /// Re-centres on the current attitude.
    public func recentre() {
        reference = nil
    }

    private func ingest(_ attitude: CMAttitude) {
        guard let relative = attitude.copy() as? CMAttitude else { return }
        if let reference {
            relative.multiply(byInverseOf: reference)
        } else {
            reference = attitude.copy() as? CMAttitude
            aim = .zero
            return
        }
        // Portrait: roll is the left/right steering tilt, pitch is top
        // toward/away. The cat follows the tilt rather than resisting it.
        aim = Point2(
            clamp(relative.roll / travel, -1, 1),
            clamp(-relative.pitch / travel, -1, 1)
        )
    }
}

#else

/// Stand-in on platforms without CoreMotion, so the view compiles unchanged.
public final class MotionSource {
    public private(set) var aim: Point2?
    public var isAvailable: Bool { false }
    public var travel: Double = 0.55

    public init() {}
    public func start() {}
    public func stop() {}
    public func recentre() {}
}

#endif
#endif
