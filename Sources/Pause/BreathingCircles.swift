import SwiftUI

private enum Breath {
    static let inhaleDuration: Double = 4
    static let holdDuration: Double = 0.9
    static let exhaleDuration: Double = 6
    static let restingScale: CGFloat = 0.55
}

/// Three concentric tinted circles that bloom on a breathing cadence, with an
/// arbitrary centred view inside them. `isAnimated` off leaves them at rest,
/// which is how the manual-return screen shows the same shape settled.
struct BreathingCircles<Center: View>: View {
    var isAnimated: Bool = true
    @ViewBuilder var center: () -> Center

    @State private var isInhaled = false

    private struct Ring {
        let radius: CGFloat
        let opacity: Double
        let delay: Double
    }

    private static var rings: [Ring] {
        [
            Ring(radius: 130, opacity: 0.07, delay: 0),
            Ring(radius: 100, opacity: 0.10, delay: 0.25),
            Ring(radius: 70, opacity: 0.16, delay: 0.5),
        ]
    }


    var body: some View {
        ZStack {
            ZStack {
                ForEach(Array(Self.rings.enumerated()), id: \.offset) { _, ring in
                    Circle()
                        .fill(Color.pauseTint.opacity(ring.opacity))
                        .frame(width: ring.radius * 2, height: ring.radius * 2)
                        .scaleEffect(scale)
                        .animation(animation(delay: ring.delay), value: isInhaled)
                }
            }
            .accessibilityHidden(true)

            center()
        }
        .frame(width: Self.rings[0].radius * 2, height: Self.rings[0].radius * 2)
        .task {
            guard isAnimated else { return }
            while !Task.isCancelled {
                isInhaled = true
                try? await Task.sleep(for: .seconds(Breath.inhaleDuration + Breath.holdDuration))
                guard !Task.isCancelled else { return }
                isInhaled = false
                try? await Task.sleep(for: .seconds(Breath.exhaleDuration))
            }
        }
    }

    private var scale: CGFloat {
        guard isAnimated else { return 1 }
        return isInhaled ? 1 : Breath.restingScale
    }

    /// Inhale and exhale differ in length, so the curve is picked from the
    /// value being animated *to* rather than set once.
    private func animation(delay: Double) -> Animation {
        let duration = isInhaled ? Breath.inhaleDuration : Breath.exhaleDuration
        return .timingCurve(0.42, 0, 0.34, 1, duration: duration).delay(delay)
    }
}

extension BreathingCircles where Center == EmptyView {
    init(isAnimated: Bool = true) {
        self.init(isAnimated: isAnimated) { EmptyView() }
    }
}
