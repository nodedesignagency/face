import XCTest

@testable import FaceEngine

final class RigTests: XCTestCase {
    private let rig = CatRig()

    private func points(in drawing: FaceDrawing) -> [Point2] {
        drawing.shapes.flatMap { shape in
            shape.commands.flatMap { command -> [Point2] in
                switch command {
                case .move(let p), .line(let p): return [p]
                case .quad(let c, let p): return [c, p]
                case .cubic(let c1, let c2, let p): return [c1, c2, p]
                case .close: return []
                }
            }
        }
    }

    func testEveryPoseProducesFiniteGeometry() {
        for yaw in stride(from: -0.8, through: 0.8, by: 0.1) {
            for pitch in stride(from: -0.45, through: 0.45, by: 0.15) {
                let state = FaceState(pose: Pose(yaw: yaw, pitch: pitch, roll: yaw * -0.2))
                let drawing = rig.draw(state)
                XCTAssertFalse(drawing.shapes.isEmpty)
                for point in points(in: drawing) {
                    XCTAssertTrue(
                        point.x.isFinite && point.y.isFinite,
                        "non-finite point at yaw \(yaw) pitch \(pitch)"
                    )
                }
            }
        }
    }

    func testArtworkStaysInsideTheCanvasAcrossTheFullRange() {
        let limits = PoseLimits.default
        // A generous margin: strokes are centred on the path, so a little
        // overshoot is fine, a lot means the composition is wrong.
        let margin = 40.0
        for yaw in stride(from: -limits.yaw, through: limits.yaw, by: 0.12) {
            for pitch in stride(from: -limits.pitch, through: limits.pitch, by: 0.1) {
                let state = FaceState(
                    pose: Pose(yaw: yaw, pitch: pitch, roll: -yaw * limits.roll)
                )
                let drawing = rig.draw(state)
                for point in points(in: drawing) {
                    XCTAssertGreaterThan(point.x, -margin)
                    XCTAssertLessThan(point.x, drawing.size.x + margin)
                    XCTAssertGreaterThan(point.y, -margin)
                    XCTAssertLessThan(point.y, drawing.size.y + margin)
                }
            }
        }
    }

    func testTheHeadIsPaintedOverTheEarsAndUnderTheFace() {
        let drawing = rig.draw(FaceState())
        let filled = drawing.shapes.enumerated().filter { $0.element.style.fill == .paper }
        // Body, two ears and the head all fill with paper; the head is the last
        // of them, so the ear bases disappear into the skull.
        XCTAssertGreaterThanOrEqual(filled.count, 4)

        let inkStrokes = drawing.shapes.enumerated().filter {
            $0.element.style.stroke == .ink && $0.element.style.fill == nil
        }
        let lastPaperFill = filled.map(\.offset).max() ?? 0
        let faceLines = inkStrokes.map(\.offset).filter { $0 > lastPaperFill }
        XCTAssertFalse(faceLines.isEmpty, "face detail must be drawn after the head fill")
    }

    func testBlinkReplacesTheOpenEyeWithALid() {
        let open = rig.draw(FaceState(blink: 0))
        let shut = rig.draw(FaceState(blink: 1))

        // The pupils and their glints are gone once the lids are down.
        let openInkFills = open.shapes.filter { $0.style.fill == .ink }.count
        let shutInkFills = shut.shapes.filter { $0.style.fill == .ink }.count
        XCTAssertGreaterThan(openInkFills, shutInkFills)
        XCTAssertFalse(shut.shapes.isEmpty)
    }

    func testRigOverlayOnlyAppearsWhenAsked() {
        let plain = rig.draw(FaceState(showRig: false))
        let exposed = rig.draw(FaceState(showRig: true))
        XCTAssertTrue(plain.shapes.allSatisfy { $0.style.stroke != .guide && $0.style.fill != .guide })
        XCTAssertTrue(exposed.shapes.contains { $0.style.stroke == .guide })
        XCTAssertGreaterThan(exposed.shapes.count, plain.shapes.count)
    }

    func testTurningTheHeadRedrawsTheMarkingsItCanSee() {
        func markings(_ state: FaceState) -> [Shape2D] {
            rig.draw(state).shapes.filter { $0.style.stroke == .marking }
        }
        let rest = markings(FaceState())
        let turned = markings(FaceState(pose: Pose(yaw: 0.7)))

        XCTAssertFalse(rest.isEmpty)
        XCTAssertFalse(turned.isEmpty)
        // Every stripe is re-solved against the new pose, so none of the drawn
        // geometry survives a turn unchanged.
        XCTAssertTrue(Set(rest.map(\.commands)).isDisjoint(with: Set(turned.map(\.commands))))
    }

    func testMarkingsFadeRatherThanSnapAtTheRim() {
        // Sweep through a turn watching the faintest stripe on screen. Stripes
        // have to arrive and leave gradually; one that pops on at full strength
        // reads as a glitch on the outline rather than a marking on a skull.
        var faintest: [Double] = []
        for yaw in stride(from: -0.9, through: 0.9, by: 0.05) {
            let opacities = rig.draw(FaceState(pose: Pose(yaw: yaw))).shapes
                .filter { $0.style.stroke == .marking }
                .map(\.style.opacity)
            XCTAssertFalse(opacities.isEmpty, "markings vanished entirely at yaw \(yaw)")
            XCTAssertTrue(opacities.allSatisfy { $0 > 0 && $0 <= 1 })
            faintest.append(opacities.min() ?? 1)
        }
        XCTAssertTrue(
            faintest.contains { $0 < 0.99 && $0 > 0.02 },
            "no stripe was ever caught part-way through its fade"
        )
    }

    func testStripesBehindTheEarStayHiddenUntilTheHeadTurns() {
        func count(_ yaw: Double) -> Int {
            rig.draw(FaceState(pose: Pose(yaw: yaw))).shapes
                .filter { $0.style.stroke == .marking }
                .count
        }
        // Head-on, both sets of rearmost stripes are culled. Turning trades the
        // far side's stripes for the near side's, so the count must move.
        XCTAssertNotEqual(count(0), count(0.7))
    }

    func testEverythingPaintedOnTheSkullIsClippedToIt() {
        let drawing = rig.draw(FaceState(pose: Pose(yaw: 0.7)))
        XCTAssertFalse(drawing.headOutline.isEmpty)

        // Near the rim a feature's frame flattens but never disappears, so the
        // face detail has to be cut off at the silhouette.
        let clipped = drawing.shapes.filter(\.clipsToHead)
        XCTAssertGreaterThan(clipped.count, 5)
        // The head fill, the ears, the whiskers and the body are not.
        XCTAssertTrue(drawing.shapes.contains { !$0.clipsToHead && $0.style.fill == .paper })
    }

    func testFeaturesTravelWithTheHeadTurn() {
        let rest = rig.draw(FaceState())
        let turned = rig.draw(FaceState(pose: Pose(yaw: 0.5)))
        let restCentroid = centroid(points(in: rest))
        let turnedCentroid = centroid(points(in: turned))
        XCTAssertGreaterThan(turnedCentroid.x, restCentroid.x + 2)
    }

    private func centroid(_ points: [Point2]) -> Point2 {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(Point2.zero, +)
        return sum / Double(points.count)
    }

    func testSVGExportProducesParseablePathData() {
        let drawing = rig.draw(FaceState(showRig: true))
        let svg = SVGExport.string(for: drawing)
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.hasSuffix("</svg>"))
        XCTAssertFalse(svg.contains("nan"))
        XCTAssertFalse(svg.contains("inf"))

        // One path per shape, plus the one inside the head clipPath.
        XCTAssertEqual(svg.components(separatedBy: "<path").count - 1, drawing.shapes.count + 1)
        XCTAssertTrue(svg.contains("<clipPath"))
        XCTAssertEqual(
            svg.components(separatedBy: "clip-path=\"url(#").count - 1,
            drawing.shapes.filter(\.clipsToHead).count
        )
    }

    func testTwoDrawingsInOneDocumentDoNotShareAClipID() {
        // The contact sheet inlines several faces side by side; a fixed id would
        // make every one of them clip to the first head.
        let first = SVGExport.string(for: rig.draw(FaceState()))
        let second = SVGExport.string(for: rig.draw(FaceState()))
        func clipID(_ svg: String) -> Substring {
            svg.split(separator: "id=\"")[1].split(separator: "\"")[0]
        }
        XCTAssertNotEqual(clipID(first), clipID(second))
    }
}
