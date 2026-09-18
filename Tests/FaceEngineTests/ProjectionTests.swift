import XCTest

@testable import FaceEngine

final class ProjectionTests: XCTestCase {
    private let head = HeadShape(radius: 150)
    private let center = Point2(260, 250)

    private func projector(yaw: Double = 0, pitch: Double = 0, roll: Double = 0) -> Projector {
        Projector(pose: Pose(yaw: yaw, pitch: pitch, roll: roll), head: head, center: center)
    }

    func testFrontOfHeadProjectsToCentre() {
        let point = projector().project(Vec3(0, 0, 1)).position
        XCTAssertEqual(point.x, center.x, accuracy: 1e-9)
        XCTAssertEqual(point.y, center.y, accuracy: 1e-9)
    }

    func testPositiveYawMovesTheNoseToTheViewersRight() {
        let nose = Vec3.onSphere(lon: 0, lat: 0)
        let turned = projector(yaw: 0.5).project(nose).position
        XCTAssertGreaterThan(turned.x, center.x)
    }

    func testPositivePitchLiftsTheMuzzle() {
        let muzzle = Vec3.onSphere(lon: 0, lat: -0.2)
        let rest = projector().project(muzzle).position
        let lifted = projector(pitch: 0.4).project(muzzle).position
        // Canvas y grows downward, so lifting means a smaller y.
        XCTAssertLessThan(lifted.y, rest.y)
    }

    func testRotationPreservesLength() {
        let projector = self.projector(yaw: 0.7, pitch: -0.3, roll: 0.2)
        for vector in [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0.3, -0.5, 0.8)] {
            XCTAssertEqual(projector.rotate(vector).length, vector.length, accuracy: 1e-12)
        }
    }

    func testFeaturesRoundOutOfSightWhenTheHeadTurnsAway() {
        let lon = 0.455
        XCTAssertGreaterThan(projector().tangentFrame(lon: lon, lat: 0).facing, 0.85)

        // Yaw adds to a feature's longitude, so turning the head to the viewer's
        // right carries the right-hand eye past the rim and out of sight.
        let turned = projector(yaw: 1.4).tangentFrame(lon: lon, lat: 0)
        XCTAssertLessThan(turned.facing, 0)
        XCTAssertEqual(turned.visibility(), 0, accuracy: 1e-9)
    }

    func testVisibilityFallsOffMonotonicallyWithTheTurn() {
        var previous = Double.infinity
        for yaw in stride(from: 0.0, through: 1.6, by: 0.05) {
            let visibility = projector(yaw: yaw).tangentFrame(lon: 0, lat: 0).visibility()
            XCTAssertLessThanOrEqual(visibility, previous + 1e-12)
            previous = visibility
        }
        XCTAssertEqual(projector().tangentFrame(lon: 0, lat: 0).visibility(), 1, accuracy: 1e-9)
        XCTAssertEqual(projector(yaw: 1.6).tangentFrame(lon: 0, lat: 0).visibility(), 0, accuracy: 1e-9)
    }

    func testSmoothstepRampsBothWays() {
        XCTAssertEqual(smoothstep(0, 1, -1), 0, accuracy: 1e-12)
        XCTAssertEqual(smoothstep(0, 1, 2), 1, accuracy: 1e-12)
        XCTAssertEqual(smoothstep(0, 1, 0.5), 0.5, accuracy: 1e-12)

        // A descending range has to ramp the other way. Getting this wrong left
        // the closed-eyelid arc drawn at full strength over every open eye.
        XCTAssertEqual(smoothstep(0.34, 0.06, 1.0), 0, accuracy: 1e-12)
        XCTAssertEqual(smoothstep(0.34, 0.06, 0.0), 1, accuracy: 1e-12)
        XCTAssertEqual(smoothstep(0.34, 0.06, 0.2), 0.5, accuracy: 0.05)
    }

    func testAStripeBehindTheEarIsHiddenAtRestAndRevealedByATurn() {
        // The wrap-around payoff: markings the viewer has never seen come into
        // view on a hard turn. If this stops holding, the head reads as flat.
        let stripe = (0...12).map { index in
            Vec3.onSphere(lon: 1.49, lat: 0.42 - Double(index) / 12 * 0.36)
        }
        XCTAssertTrue(projector().visibleRuns(stripe, threshold: 0.25).isEmpty)
        XCTAssertFalse(projector(yaw: -0.7).visibleRuns(stripe, threshold: 0.25).isEmpty)
    }

    func testTangentFrameFlattensAsItApproachesTheRim() {
        // A feature seen straight on occupies more canvas than the same feature
        // rotated toward the edge. This foreshortening is the illusion.
        let straightOn = projector().tangentFrame(lon: 0, lat: 0)
        let nearRim = projector(yaw: 1.1).tangentFrame(lon: 0, lat: 0)
        XCTAssertGreaterThan(abs(straightOn.transform.determinant), abs(nearRim.transform.determinant))
    }

    func testTangentFrameIsUprightAndUnflippedWhenFacingForward() {
        // Square to the camera the frame is a pure uniform scale — no rotation,
        // no shear, no mirroring. The scale is above 1 because the front of the
        // head is nearer than its centre.
        let frame = projector().tangentFrame(lon: 0, lat: 0)
        XCTAssertGreaterThan(frame.scale, 1)
        XCTAssertEqual(frame.transform.a, frame.scale, accuracy: 1e-9)
        XCTAssertEqual(frame.transform.d, frame.scale, accuracy: 1e-9)
        XCTAssertEqual(frame.transform.b, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.transform.c, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(frame.transform.determinant, 0)
    }

    func testLiftedFrameParallaxesAgainstTheSurface() {
        // The pupil trick: at rest the lifted frame sits on top of the flat one,
        // and once the head turns it slides away from it.
        let restSurface = projector().tangentFrame(lon: 0.455, lat: 0).origin
        let restLifted = projector().tangentFrame(lon: 0.455, lat: 0, lift: 0.05).origin
        let restOffset = abs(restLifted.x - restSurface.x)

        let turnedSurface = projector(yaw: 0.6).tangentFrame(lon: 0.455, lat: 0).origin
        let turnedLifted = projector(yaw: 0.6).tangentFrame(lon: 0.455, lat: 0, lift: 0.05).origin
        let turnedOffset = abs(turnedLifted.x - turnedSurface.x)

        XCTAssertGreaterThan(turnedOffset, restOffset + 1)
    }

    func testSilhouetteNarrowsWithYawAndStaysPositive() {
        let front = projector().silhouette
        let turned = projector(yaw: 0.8).silhouette
        XCTAssertEqual(front.halfWidth, 150, accuracy: 1e-9)
        XCTAssertLessThan(turned.halfWidth, front.halfWidth)
        XCTAssertGreaterThan(turned.halfWidth, 130)
        // Yaw must not disturb the height.
        XCTAssertEqual(turned.halfHeight, front.halfHeight, accuracy: 1e-9)
    }

    func testVisibleRunsSplitAWrappingStripe() {
        // A full ring around the head is visible only on the near side, and it
        // must come back as one unbroken run rather than a smear across the face.
        let ring = stride(from: -180.0, through: 180.0, by: 4.0).map {
            Vec3.onSphere(lon: $0 * .pi / 180, lat: 0)
        }
        let runs = projector().visibleRuns(ring)
        XCTAssertEqual(runs.count, 1)
        XCTAssertLessThan(runs[0].count, ring.count)
        XCTAssertGreaterThan(runs[0].count, 10)
    }
}
