#if canImport(SwiftUI)
import CoreGraphics
import FaceEngine
import Foundation

public enum TrackingSource: String, CaseIterable, Identifiable, Sendable {
    case pointer
    case motion

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pointer: return "Touch"
        case .motion: return "Tilt"
        }
    }
}

/// Holds the animation state across frames.
///
/// Deliberately a reference type with no published properties: `TimelineView`
/// already redraws every frame, so publishing from here would only invalidate
/// the view a second time per frame. It is driven from the `Canvas` renderer,
/// which runs on the main thread.
public final class FaceModel: ObservableObject {
    public let rig: CatRig
    public private(set) var animator: FaceAnimator
    public var showRig = false
    public var reduceMotion = false

    private var origin: Date?

    public init(rig: CatRig = CatRig(), seed: UInt64 = 0x5EED_CA7) {
        self.rig = rig
        self.animator = FaceAnimator(seed: seed)
    }

    /// Seconds since the first frame.
    public func elapsed(at date: Date) -> Double {
        guard let origin else {
            self.origin = date
            return 0
        }
        return date.timeIntervalSince(origin)
    }

    public func look(at aim: Point2, date: Date) {
        animator.look(at: aim, time: elapsed(at: date))
    }

    public func stopTracking(date: Date) {
        animator.releaseTracking(time: elapsed(at: date))
    }

    /// Advances to `date` and returns the frame to draw.
    public func frame(at date: Date) -> FaceDrawing {
        let time = elapsed(at: date)
        // Someone who has asked for less motion still gets the head turn they
        // are driving themselves — what goes is the unprompted wandering.
        animator.idleDelay = reduceMotion ? .greatestFiniteMagnitude : 2.4
        animator.advance(to: time)
        return rig.draw(animator.state(at: time, showRig: showRig))
    }

    /// Converts a point in view coordinates to the animator's -1...1 aim space.
    public static func normalize(_ point: CGPoint, in size: CGSize) -> Point2 {
        guard size.width > 0, size.height > 0 else { return .zero }
        return Point2(
            clamp(Double(point.x / size.width) * 2 - 1, -1, 1),
            clamp(Double(point.y / size.height) * 2 - 1, -1, 1)
        )
    }
}
#endif
