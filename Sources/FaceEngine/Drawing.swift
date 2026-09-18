import Foundation

/// A semantic colour role. The engine never names an actual colour, so the
/// same drawing renders correctly in light mode, dark mode, or an SVG export.
public enum Paint: String, Hashable, Sendable, CaseIterable {
    /// The rim that separates the head from the body. On a black cat there is
    /// no outline to speak of — this is a hair lighter than the coat, read as
    /// light catching the edge of the fur.
    case ink
    /// The coat: head, ears and body.
    case fur
    /// The amber ring of the eye.
    case iris
    /// The pupil inside it.
    case pupil
    /// Catchlight.
    case glint
    /// Warm inner ear.
    case innerEar
    /// The nose.
    case nose
    /// Whiskers, ear tufts and the stray hairs off the crown.
    case whisker
    /// Sheen wrapping the skull. Not tabby stripes — light grazing dark fur.
    case marking
    /// The rim light down the lit edge of the head.
    case sheen
    /// The head's shadow falling on the chest. Darker than the coat.
    case shadow
    /// Soft detail: the mouth and the whisker-pad dots.
    case shade
    /// Construction lines, only visible when the rig overlay is on.
    case guide
}

public enum LineCap: Hashable, Sendable {
    case butt, round, square
}

public enum LineJoin: Hashable, Sendable {
    case miter, round, bevel
}

public struct Style: Hashable, Sendable {
    public var fill: Paint?
    public var stroke: Paint?
    public var lineWidth: Double
    public var cap: LineCap
    public var join: LineJoin
    public var opacity: Double
    public var dash: [Double]

    public init(
        fill: Paint? = nil,
        stroke: Paint? = nil,
        lineWidth: Double = 0,
        cap: LineCap = .round,
        join: LineJoin = .round,
        opacity: Double = 1,
        dash: [Double] = []
    ) {
        self.fill = fill
        self.stroke = stroke
        self.lineWidth = lineWidth
        self.cap = cap
        self.join = join
        self.opacity = opacity
        self.dash = dash
    }

    public static func stroked(
        _ paint: Paint = .ink,
        width: Double,
        opacity: Double = 1,
        cap: LineCap = .round,
        dash: [Double] = []
    ) -> Style {
        Style(stroke: paint, lineWidth: width, cap: cap, opacity: opacity, dash: dash)
    }

    public static func filled(_ paint: Paint, opacity: Double = 1) -> Style {
        Style(fill: paint, opacity: opacity)
    }

    public static func outlined(
        fill: Paint,
        stroke: Paint = .ink,
        width: Double,
        opacity: Double = 1
    ) -> Style {
        Style(fill: fill, stroke: stroke, lineWidth: width, opacity: opacity)
    }

    public func opacity(_ value: Double) -> Style {
        var copy = self
        copy.opacity = value
        return copy
    }
}

public enum PathCommand: Hashable, Sendable {
    case move(Point2)
    case line(Point2)
    case quad(control: Point2, to: Point2)
    case cubic(control1: Point2, control2: Point2, to: Point2)
    case close
}

public struct Shape2D: Hashable, Sendable {
    public var commands: [PathCommand]
    public var style: Style
    /// Confines this shape to the head outline.
    ///
    /// Anything painted *on* the skull needs it: near the rim a feature's
    /// tangent frame flattens but never vanishes, so an eye or a stripe would
    /// otherwise hang off the silhouette into thin air. Things that genuinely
    /// leave the head — ears, whiskers, the body — stay unclipped.
    public var clipsToHead: Bool

    public init(commands: [PathCommand], style: Style, clipsToHead: Bool = false) {
        self.commands = commands
        self.style = style
        self.clipsToHead = clipsToHead
    }

    public var isEmpty: Bool { commands.isEmpty || style.opacity <= 0.001 }

    public func clippedToHead() -> Shape2D {
        var copy = self
        copy.clipsToHead = true
        return copy
    }
}

/// One fully resolved frame: flat 2D shapes in canvas coordinates, in paint
/// order. Nothing here knows about the sphere any more.
public struct FaceDrawing: Sendable {
    public var size: Point2
    public var shapes: [Shape2D]
    /// The head outline, for shapes that ask to be clipped to it.
    public var headOutline: [PathCommand]

    public init(size: Point2, shapes: [Shape2D], headOutline: [PathCommand] = []) {
        self.size = size
        self.shapes = shapes
        self.headOutline = headOutline
    }
}

/// Small helper for assembling paths without drowning in `.move`/`.line`.
public struct PathBuilder {
    public private(set) var commands: [PathCommand] = []

    public init() {}

    public mutating func move(_ p: Point2) { commands.append(.move(p)) }
    public mutating func line(_ p: Point2) { commands.append(.line(p)) }
    public mutating func quad(_ control: Point2, _ to: Point2) {
        commands.append(.quad(control: control, to: to))
    }
    public mutating func cubic(_ c1: Point2, _ c2: Point2, _ to: Point2) {
        commands.append(.cubic(control1: c1, control2: c2, to: to))
    }
    public mutating func close() { commands.append(.close) }

    public mutating func append(_ other: [PathCommand]) { commands.append(contentsOf: other) }

    /// Magic constant for approximating a quarter circle with a cubic Bézier.
    private static let kappa = 0.5522847498307936

    public mutating func ellipse(center: Point2, rx: Double, ry: Double) {
        let ox = rx * Self.kappa
        let oy = ry * Self.kappa
        let (cx, cy) = (center.x, center.y)
        move(Point2(cx, cy - ry))
        cubic(Point2(cx + ox, cy - ry), Point2(cx + rx, cy - oy), Point2(cx + rx, cy))
        cubic(Point2(cx + rx, cy + oy), Point2(cx + ox, cy + ry), Point2(cx, cy + ry))
        cubic(Point2(cx - ox, cy + ry), Point2(cx - rx, cy + oy), Point2(cx - rx, cy))
        cubic(Point2(cx - rx, cy - oy), Point2(cx - ox, cy - ry), Point2(cx, cy - ry))
        close()
    }

    /// Transforms every point as the path is built, which is how flat local
    /// artwork gets mapped onto the rotated head.
    public static func transformed(_ commands: [PathCommand], by t: Transform2D) -> [PathCommand] {
        commands.map { command in
            switch command {
            case .move(let p): return .move(t.apply(p))
            case .line(let p): return .line(t.apply(p))
            case .quad(let c, let p): return .quad(control: t.apply(c), to: t.apply(p))
            case .cubic(let c1, let c2, let p):
                return .cubic(control1: t.apply(c1), control2: t.apply(c2), to: t.apply(p))
            case .close: return .close
            }
        }
    }
}
