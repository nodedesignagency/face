import FaceEngine
import Foundation

// Renders a contact sheet of poses as SVG, for tuning the face without
// launching the app.
//
//   swift run face-preview [output-directory]

let arguments = CommandLine.arguments
let outputDirectory = arguments.count > 1 ? arguments[1] : "preview"

try? FileManager.default.createDirectory(
    atPath: outputDirectory, withIntermediateDirectories: true
)

let rig = CatRig()

struct Frame {
    let name: String
    let state: FaceState
}

func degrees(_ value: Double) -> Double { value * .pi / 180 }

let frames: [Frame] = [
    Frame(name: "front", state: FaceState()),
    Frame(
        name: "left",
        state: FaceState(pose: Pose(yaw: degrees(-34), pitch: degrees(4), roll: degrees(5)))
    ),
    Frame(
        name: "right",
        state: FaceState(pose: Pose(yaw: degrees(34), pitch: degrees(4), roll: degrees(-5)))
    ),
    Frame(
        name: "up",
        state: FaceState(pose: Pose(yaw: degrees(10), pitch: degrees(22)))
    ),
    Frame(
        name: "down",
        state: FaceState(pose: Pose(yaw: degrees(-12), pitch: degrees(-20), roll: degrees(6)))
    ),
    Frame(
        name: "hard-right",
        state: FaceState(pose: Pose(yaw: degrees(44), pitch: degrees(-6), roll: degrees(-8)))
    ),
    Frame(
        name: "blink",
        state: FaceState(pose: Pose(yaw: degrees(-18), pitch: degrees(6)), blink: 1)
    ),
    Frame(
        name: "rig",
        state: FaceState(
            pose: Pose(yaw: degrees(30), pitch: degrees(10), roll: degrees(-4)),
            showRig: true
        )
    ),
]

for frame in frames {
    let svg = SVGExport.string(for: rig.draw(frame.state), palette: .light)
    let path = "\(outputDirectory)/\(frame.name).svg"
    try svg.write(toFile: path, atomically: true, encoding: .utf8)
    print("wrote \(path)")
}

// One dark-mode still, to confirm the palette holds on the other ground.
let darkState = FaceState(pose: Pose(yaw: degrees(-26), pitch: degrees(8), roll: degrees(4)))
try SVGExport.string(for: rig.draw(darkState), palette: .dark)
    .write(toFile: "\(outputDirectory)/dark.svg", atomically: true, encoding: .utf8)
print("wrote \(outputDirectory)/dark.svg")

// A contact sheet, so a whole turn can be judged at a glance.
let sweep = stride(from: -44.0, through: 44.0, by: 11.0).map { yaw in
    FaceState(
        pose: Pose(
            yaw: degrees(yaw),
            pitch: degrees(6 * cos(degrees(yaw) * 2)),
            roll: degrees(-yaw * 0.16)
        )
    )
}
let cell = rig.canvas
let columns = 5
let rows = (sweep.count + columns - 1) / columns
var sheet = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(Int(cell.x) * columns)" \
height="\(Int(cell.y) * rows)" viewBox="0 0 \(Int(cell.x) * columns) \(Int(cell.y) * rows)">
<rect width="100%" height="100%" fill="\(PaintTable.light.background)"/>
"""
for (index, state) in sweep.enumerated() {
    let x = Double(index % columns) * cell.x
    let y = Double(index / columns) * cell.y
    let inner = SVGExport.string(for: rig.draw(state), palette: .light, drawBackground: false)
    sheet += "<g transform=\"translate(\(Int(x)) \(Int(y)))\">\(inner)</g>"
}
sheet += "</svg>"
try sheet.write(toFile: "\(outputDirectory)/sheet.svg", atomically: true, encoding: .utf8)
print("wrote \(outputDirectory)/sheet.svg")
