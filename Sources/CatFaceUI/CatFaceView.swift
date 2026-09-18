#if canImport(SwiftUI)
import Combine
import FaceEngine
import Foundation
import SwiftUI

/// The cat, and the handful of controls that drive it.
public struct CatFaceView: View {
    @StateObject private var model = FaceModel()
    @StateObject private var motion = MotionController()

    @State private var source: TrackingSource = .pointer
    @State private var showRig = false
    @State private var hasInteracted = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var palette: CatPalette { .forScheme(colorScheme) }

    public var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            face
                .accessibilityElement()
                .accessibilityLabel("A cat")
                .accessibilityValue(
                    source == .pointer
                        ? "Turns its head to follow your touch"
                        : "Turns its head as you tilt the device"
                )

            VStack(spacing: 14) {
                Spacer(minLength: 0)
                hint
                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .onAppear { sync() }
        .onChange(of: source) { _ in sync() }
        .onChange(of: showRig) { newValue in model.showRig = newValue }
        .onChange(of: reduceMotion) { newValue in model.reduceMotion = newValue }
        .onDisappear { motion.stop() }
    }

    // MARK: - Face

    private var face: some View {
        GeometryReader { geometry in
            let size = geometry.size
            TimelineView(.animation) { timeline in
                Canvas(rendersAsynchronously: false) { context, canvasSize in
                    let date = timeline.date
                    if source == .motion, let aim = motion.source.aim {
                        model.look(at: aim, date: date)
                    }
                    CatFaceRenderer.draw(
                        model.frame(at: date),
                        in: &context,
                        size: canvasSize,
                        palette: palette
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard source == .pointer else { return }
                        hasInteracted = true
                        model.look(
                            at: FaceModel.normalize(value.location, in: size),
                            date: Date()
                        )
                    }
                    .onEnded { _ in
                        guard source == .pointer else { return }
                        model.stopTracking(date: Date())
                    }
            )
            .onContinuousHover { phase in
                guard source == .pointer else { return }
                switch phase {
                case .active(let location):
                    hasInteracted = true
                    model.look(at: FaceModel.normalize(location, in: size), date: Date())
                case .ended:
                    model.stopTracking(date: Date())
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Chrome

    private var hint: some View {
        Text(source == .pointer ? "Drag across the face to turn it" : "Tilt to turn the head")
            .font(.footnote.weight(.medium))
            .foregroundStyle(palette.color(.ink).opacity(0.55))
            .opacity(hasInteracted && source == .pointer ? 0 : 1)
            .animation(.easeOut(duration: 0.4), value: hasInteracted)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if motion.source.isAvailable {
                ForEach(TrackingSource.allCases) { option in
                    Pill(
                        title: option.label,
                        isOn: source == option,
                        palette: palette
                    ) {
                        source = option
                    }
                }
            }

            Spacer(minLength: 0)

            Pill(title: "Rig", isOn: showRig, palette: palette) {
                showRig.toggle()
            }
            .accessibilityHint("Shows the construction sphere the face is built on")
        }
    }

    private func sync() {
        model.showRig = showRig
        model.reduceMotion = reduceMotion
        if source == .motion {
            motion.start()
        } else {
            motion.stop()
            model.stopTracking(date: Date())
        }
    }
}

/// A compact toggle styled to sit alongside the illustration rather than on top
/// of it — the drawing is the interface, these are just switches.
private struct Pill: View {
    let title: String
    let isOn: Bool
    let palette: CatPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(isOn ? palette.color(.paper) : palette.color(.ink))
                .background {
                    Capsule()
                        .fill(isOn ? palette.color(.ink) : .clear)
                        .overlay {
                            Capsule().strokeBorder(
                                palette.color(.ink).opacity(isOn ? 0 : 0.28),
                                lineWidth: 1.5
                            )
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Wraps `MotionSource` so the view can hold it in `@StateObject`.
private final class MotionController: ObservableObject {
    let source = MotionSource()

    func start() { source.start() }
    func stop() { source.stop() }
}

struct CatFaceView_Previews: PreviewProvider {
    static var previews: some View {
        CatFaceView()
    }
}
#endif
