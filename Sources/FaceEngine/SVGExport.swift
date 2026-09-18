import Foundation

/// Hex colours for each semantic paint.
public struct PaintTable: Sendable {
    public var values: [Paint: String]
    public var background: String

    public init(values: [Paint: String], background: String) {
        self.values = values
        self.background = background
    }

    public subscript(paint: Paint) -> String {
        values[paint] ?? "#000000"
    }

    public static let light = PaintTable(
        values: [
            .ink: "#34343F",
            .fur: "#1B1B22",
            .iris: "#F7C63E",
            .pupil: "#141018",
            .glint: "#FFFFFF",
            .innerEar: "#E8913F",
            .nose: "#57393E",
            .whisker: "#F0E6D2",
            .marking: "#3C3C49",
            .shade: "#4E4E5B",
            .guide: "#6FE3FF",
        ],
        background: "#45A79E"
    )

    /// The cat itself barely changes — a black cat is a black cat. What moves
    /// is the ground it sits on and the rim that lifts it off that ground.
    public static let dark = PaintTable(
        values: [
            .ink: "#41414F",
            .fur: "#131319",
            .iris: "#F5C33A",
            .pupil: "#0D0A11",
            .glint: "#FFF8E8",
            .innerEar: "#D9823A",
            .nose: "#5E4045",
            .whisker: "#E4D9C4",
            .marking: "#32323E",
            .shade: "#44444F",
            .guide: "#6FE3FF",
        ],
        background: "#10403F"
    )
}

/// Writes a `FaceDrawing` out as SVG.
///
/// Keeps the engine useful outside the app — exporting stills, and checking the
/// rig on a machine with no Apple frameworks on it.
public enum SVGExport {
    public static func string(
        for drawing: FaceDrawing,
        palette: PaintTable = .light,
        drawBackground: Bool = true
    ) -> String {
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(drawing.size.x))" \
        height="\(fmt(drawing.size.y))" viewBox="0 0 \(fmt(drawing.size.x)) \(fmt(drawing.size.y))">
        """
        if drawBackground {
            svg += """
            <rect width="\(fmt(drawing.size.x))" height="\(fmt(drawing.size.y))" \
            fill="\(palette.background)"/>
            """
        }

        // Several of these can share one document, so the clip id has to be
        // unique per drawing, not a constant.
        let clipID = "head-\(UInt32.random(in: 0..<UInt32.max))"
        let needsClip = !drawing.headOutline.isEmpty
            && drawing.shapes.contains { $0.clipsToHead }
        if needsClip {
            svg += """
            <defs><clipPath id="\(clipID)">\
            <path d="\(pathData(drawing.headOutline))"/></clipPath></defs>
            """
        }

        for shape in drawing.shapes {
            svg += element(
                for: shape,
                palette: palette,
                clipID: needsClip && shape.clipsToHead ? clipID : nil
            )
        }
        svg += "</svg>"
        return svg
    }

    private static func element(
        for shape: Shape2D, palette: PaintTable, clipID: String? = nil
    ) -> String {
        var attributes = ["d=\"\(pathData(shape.commands))\""]
        if let clipID {
            attributes.append("clip-path=\"url(#\(clipID))\"")
        }

        if let fill = shape.style.fill {
            attributes.append("fill=\"\(palette[fill])\"")
        } else {
            attributes.append("fill=\"none\"")
        }
        if let stroke = shape.style.stroke, shape.style.lineWidth > 0 {
            attributes.append("stroke=\"\(palette[stroke])\"")
            attributes.append("stroke-width=\"\(fmt(shape.style.lineWidth))\"")
            attributes.append("stroke-linecap=\"\(name(shape.style.cap))\"")
            attributes.append("stroke-linejoin=\"\(name(shape.style.join))\"")
            if !shape.style.dash.isEmpty {
                attributes.append("stroke-dasharray=\"\(shape.style.dash.map(fmt).joined(separator: " "))\"")
            }
        }
        if shape.style.opacity < 0.999 {
            attributes.append("opacity=\"\(fmt(shape.style.opacity))\"")
        }
        return "<path \(attributes.joined(separator: " "))/>"
    }

    public static func pathData(_ commands: [PathCommand]) -> String {
        commands.map { command in
            switch command {
            case .move(let p): return "M\(fmt(p.x)) \(fmt(p.y))"
            case .line(let p): return "L\(fmt(p.x)) \(fmt(p.y))"
            case .quad(let c, let p): return "Q\(fmt(c.x)) \(fmt(c.y)) \(fmt(p.x)) \(fmt(p.y))"
            case .cubic(let c1, let c2, let p):
                return "C\(fmt(c1.x)) \(fmt(c1.y)) \(fmt(c2.x)) \(fmt(c2.y)) \(fmt(p.x)) \(fmt(p.y))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }

    private static func name(_ cap: LineCap) -> String {
        switch cap {
        case .butt: return "butt"
        case .round: return "round"
        case .square: return "square"
        }
    }

    private static func name(_ join: LineJoin) -> String {
        switch join {
        case .miter: return "miter"
        case .round: return "round"
        case .bevel: return "bevel"
        }
    }

    private static func fmt(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(rounded)
    }
}
