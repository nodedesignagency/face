#if canImport(SwiftUI)
import FaceEngine
import SwiftUI

/// Paints a `FaceDrawing` into a SwiftUI `Canvas`.
public enum CatFaceRenderer {
    /// Draws the face scaled to fit `size`, centred.
    public static func draw(
        _ drawing: FaceDrawing,
        in context: inout GraphicsContext,
        size: CGSize,
        palette: CatPalette
    ) {
        guard drawing.size.x > 0, drawing.size.y > 0 else { return }

        let scale = min(size.width / drawing.size.x, size.height / drawing.size.y)
        context.translateBy(
            x: (size.width - drawing.size.x * scale) / 2,
            y: (size.height - drawing.size.y * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)

        // One clipped copy of the context, reused by every shape painted on the
        // skull. GraphicsContext is a value type, so this costs nothing and
        // leaves the unclipped context intact for the ears and whiskers.
        var headContext = context
        if !drawing.headOutline.isEmpty {
            headContext.clip(to: path(for: drawing.headOutline))
        }

        for shape in drawing.shapes {
            let target = shape.clipsToHead ? headContext : context
            render(shape, in: target, palette: palette)
        }
    }

    private static func render(_ shape: Shape2D, in context: GraphicsContext, palette: CatPalette) {
        let path = path(for: shape.commands)
        let opacity = shape.style.opacity

        if let fill = shape.style.fill {
            context.fill(path, with: .color(palette.color(fill).opacity(opacity)))
        }
        if let stroke = shape.style.stroke, shape.style.lineWidth > 0 {
            context.stroke(
                path,
                with: .color(palette.color(stroke).opacity(opacity)),
                style: StrokeStyle(
                    lineWidth: shape.style.lineWidth,
                    lineCap: cap(shape.style.cap),
                    lineJoin: join(shape.style.join),
                    dash: shape.style.dash.map { CGFloat($0) }
                )
            )
        }
    }

    public static func path(for commands: [PathCommand]) -> Path {
        var path = Path()
        for command in commands {
            switch command {
            case .move(let p):
                path.move(to: CGPoint(x: p.x, y: p.y))
            case .line(let p):
                path.addLine(to: CGPoint(x: p.x, y: p.y))
            case .quad(let control, let p):
                path.addQuadCurve(
                    to: CGPoint(x: p.x, y: p.y),
                    control: CGPoint(x: control.x, y: control.y)
                )
            case .cubic(let c1, let c2, let p):
                path.addCurve(
                    to: CGPoint(x: p.x, y: p.y),
                    control1: CGPoint(x: c1.x, y: c1.y),
                    control2: CGPoint(x: c2.x, y: c2.y)
                )
            case .close:
                path.closeSubpath()
            }
        }
        return path
    }

    private static func cap(_ cap: FaceEngine.LineCap) -> CGLineCap {
        switch cap {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    private static func join(_ join: FaceEngine.LineJoin) -> CGLineJoin {
        switch join {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
#endif
