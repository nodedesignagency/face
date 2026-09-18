import XCTest

@testable import FaceEngine

final class AnimatorTests: XCTestCase {
    /// Runs the animator forward at a fixed frame rate.
    private func run(
        _ animator: inout FaceAnimator,
        seconds: Double,
        from start: Double = 0,
        fps: Double = 60,
        step: ((Double, FaceAnimator) -> Void)? = nil
    ) {
        let frames = Int(seconds * fps)
        for i in 0...frames {
            let time = start + Double(i) / fps
            animator.advance(to: time)
            step?(time, animator)
        }
    }

    func testHeadSettlesOnTheTrackedPoint() {
        var animator = FaceAnimator()
        animator.look(at: Point2(1, 0), time: 0)
        run(&animator, seconds: 3)
        XCTAssertEqual(animator.pose.yaw, animator.limits.yaw, accuracy: 0.01)
    }

    func testHeadNeverExceedsItsLimits() {
        var animator = FaceAnimator()
        var peak = Pose()
        // Slam the aim between extremes; an underdamped spring overshoots, and
        // the overshoot still must not fold the face inside out.
        for i in 0..<12 {
            let side: Double = i.isMultiple(of: 2) ? 1 : -1
            animator.look(at: Point2(side, side), time: Double(i) * 0.25)
            run(&animator, seconds: 0.25, from: Double(i) * 0.25) { _, animator in
                peak.yaw = max(peak.yaw, abs(animator.pose.yaw))
                peak.pitch = max(peak.pitch, abs(animator.pose.pitch))
                peak.roll = max(peak.roll, abs(animator.pose.roll))
            }
        }
        XCTAssertLessThan(peak.yaw, animator.limits.yaw * 1.25)
        XCTAssertLessThan(peak.pitch, animator.limits.pitch * 1.25)
        XCTAssertLessThan(peak.roll, animator.limits.roll * 1.25)
    }

    func testOutOfRangeAimIsClamped() {
        var animator = FaceAnimator()
        animator.look(at: Point2(9, -9), time: 0)
        run(&animator, seconds: 3)
        XCTAssertEqual(animator.pose.yaw, animator.limits.yaw, accuracy: 0.01)
        XCTAssertEqual(animator.pose.pitch, animator.limits.pitch, accuracy: 0.01)
    }

    func testEyesCarryTheLookOnceTheHeadRunsOutOfTravel() {
        var animator = FaceAnimator()
        animator.look(at: Point2(0, 0), time: 0)
        run(&animator, seconds: 2)
        XCTAssertEqual(animator.gaze.x, 0, accuracy: 0.05)

        animator.look(at: Point2(1, 0), time: 2)
        run(&animator, seconds: 2, from: 2)
        // Head is at its limit, so the residual look lands in the pupils.
        XCTAssertEqual(animator.gaze.x, 0, accuracy: 0.05)

        animator.look(at: Point2(0.4, 0), time: 4)
        animator.advance(to: 4.001)
        XCTAssertLessThan(animator.gaze.x, 0)
    }

    func testIdleWanderStartsOnlyAfterTheDelay() {
        var animator = FaceAnimator()
        animator.look(at: Point2(0, 0), time: 0)
        animator.releaseTracking(time: 0)

        run(&animator, seconds: animator.idleDelay * 0.7)
        XCTAssertEqual(animator.pose.yaw, 0, accuracy: 0.02)

        var travelled = 0.0
        run(&animator, seconds: 14, from: animator.idleDelay * 0.7) { _, animator in
            travelled = max(travelled, abs(animator.pose.yaw))
        }
        XCTAssertGreaterThan(travelled, 0.1)
        XCTAssertLessThan(travelled, animator.limits.yaw * 1.1)
    }

    func testTrackingSuppressesTheIdleWander() {
        var animator = FaceAnimator()
        for i in 0...200 {
            let time = Double(i) / 20
            animator.look(at: Point2(0, 0), time: time)
            animator.advance(to: time)
        }
        XCTAssertEqual(animator.pose.yaw, 0, accuracy: 0.02)
    }

    func testBlinksHappenAndAlwaysReopen() {
        var animator = FaceAnimator()
        var sawFullyClosed = false
        var maxBlink = 0.0
        run(&animator, seconds: 60) { _, animator in
            maxBlink = max(maxBlink, animator.blink)
            if animator.blink >= 0.999 { sawFullyClosed = true }
            XCTAssertTrue(animator.blink >= 0 && animator.blink <= 1)
        }
        XCTAssertTrue(sawFullyClosed, "the cat never blinked in a minute")
        XCTAssertEqual(maxBlink, 1, accuracy: 1e-9)

        // A blink is brief; the eyes must not be caught shut most of the time.
        var closedFrames = 0
        var totalFrames = 0
        var counting = FaceAnimator()
        run(&counting, seconds: 60) { _, animator in
            totalFrames += 1
            if animator.blink > 0.5 { closedFrames += 1 }
        }
        XCTAssertLessThan(Double(closedFrames) / Double(totalFrames), 0.1)
    }

    func testAnimationIsReproducibleForAGivenSeed() {
        func trace(seed: UInt64) -> [Double] {
            var animator = FaceAnimator(seed: seed)
            var samples: [Double] = []
            run(&animator, seconds: 20) { _, animator in samples.append(animator.blink) }
            return samples
        }
        XCTAssertEqual(trace(seed: 7), trace(seed: 7))
        XCTAssertNotEqual(trace(seed: 7), trace(seed: 8))
    }

    func testALongStallDoesNotFlingTheHead() {
        var animator = FaceAnimator()
        animator.look(at: Point2(1, 1), time: 0)
        animator.advance(to: 0)
        // Simulates the app being backgrounded for a minute between frames.
        animator.advance(to: 60)
        XCTAssertLessThan(abs(animator.pose.yaw), animator.limits.yaw * 1.25)
        XCTAssertTrue(animator.pose.yaw.isFinite)
    }

    func testStateFeedsTheRigWithABreathingPhase() {
        var animator = FaceAnimator()
        animator.advance(to: 1.0)
        let state = animator.state(at: 1.0)
        XCTAssertTrue(state.breath >= -1 && state.breath <= 1)
        XCTAssertEqual(state.pose.yaw, animator.pose.yaw)
        XCTAssertFalse(state.showRig)
    }
}
