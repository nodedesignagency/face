import Foundation

/// Catmull–Rom smoothing, converted to cubic Béziers.
///
/// The rig samples its outlines as plain point runs — the head silhouette, a
/// tabby stripe wrapping the skull — and leans on this to turn them into
/// curves, so nothing in the face is hand-authored Bézier control points that
/// would have to be re-tuned every time a proportion changes.
public enum Spline {
    /// Smooths a closed ring of points.
    public static func closedLoop(_ points: [Point2], tension: Double = 1) -> [PathCommand] {
        guard points.count > 2 else { return polyline(points, closed: true) }

        var builder = PathBuilder()
        builder.move(points[0])
        let n = points.count

        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let (c1, c2) = controlPoints(p0, p1, p2, p3, tension: tension)
            builder.cubic(c1, c2, p2)
        }
        builder.close()
        return builder.commands
    }

    /// Smooths an open run of points, duplicating the endpoints so the curve
    /// starts and ends exactly where the run does.
    public static func openCurve(_ points: [Point2], tension: Double = 1) -> [PathCommand] {
        guard points.count > 2 else { return polyline(points, closed: false) }

        var builder = PathBuilder()
        builder.move(points[0])

        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let (c1, c2) = controlPoints(p0, p1, p2, p3, tension: tension)
            builder.cubic(c1, c2, p2)
        }
        return builder.commands
    }

    public static func polyline(_ points: [Point2], closed: Bool) -> [PathCommand] {
        guard let first = points.first else { return [] }
        var builder = PathBuilder()
        builder.move(first)
        for point in points.dropFirst() { builder.line(point) }
        if closed { builder.close() }
        return builder.commands
    }

    private static func controlPoints(
        _ p0: Point2, _ p1: Point2, _ p2: Point2, _ p3: Point2, tension: Double
    ) -> (Point2, Point2) {
        let k = tension / 6
        let c1 = Point2(p1.x + (p2.x - p0.x) * k, p1.y + (p2.y - p0.y) * k)
        let c2 = Point2(p2.x - (p3.x - p1.x) * k, p2.y - (p3.y - p1.y) * k)
        return (c1, c2)
    }
}
