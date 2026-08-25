import SwiftUI

private enum Pulse {
    static let expandDuration: Double = 4
    static let holdDuration: Double = 0.9
    static let contractDuration: Double = 6
    static let restingScale: CGFloat = 0.55

    /// The space the circles reserve in a layout. The breath is a
    /// render-time `scaleEffect`, so the circles draw far outside this box —
    /// deliberately, spreading off the screen edges like a ripple — without
    /// reflowing anything around them. Sized to hold the surrounding vertical
    /// rhythm steady, not to contain the circles.
    static let layoutSize: CGFloat = 260
}

/// Three concentric tinted circles that expand and contract on a slow loop,
/// with an arbitrary centred view inside them. `isAnimated` off leaves them
/// at rest, which is how the manual-return screen shows the same shape
/// settled.
///
/// The innermost circle is sized so that at the bottom of the breath — its
/// resting scale — it still fully contains the centre content: the 52pt
/// numeral over the 15pt caption measures 100 x 86pt at its widest, a 132pt
/// diagonal, against a resting inner diameter of 294 x 0.55 = 161.7pt.
struct PulsingCircles<Center: View>: View {
    var isAnimated: Bool = true
    @ViewBuilder var center: () -> Center

    @State private var isExpanded = false

    private struct Ring {
        let radius: CGFloat
        let opacity: Double
        let delay: Double
    }

    private static var rings: [Ring] {
        [
            Ring(radius: 273, opacity: 0.07, delay: 0),
            Ring(radius: 210, opacity: 0.10, delay: 0.25),
            Ring(radius: 147, opacity: 0.16, delay: 0.5),
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
                        .animation(animation(delay: ring.delay), value: isExpanded)
                }
            }
            .accessibilityHidden(true)

            center()
        }
        .frame(width: Pulse.layoutSize, height: Pulse.layoutSize)
        .task {
            guard isAnimated else { return }
            while !Task.isCancelled {
                isExpanded = true
                try? await Task.sleep(for: .seconds(Pulse.expandDuration + Pulse.holdDuration))
                guard !Task.isCancelled else { return }
                isExpanded = false
                try? await Task.sleep(for: .seconds(Pulse.contractDuration))
            }
        }
    }

    private var scale: CGFloat {
        guard isAnimated else { return Pulse.restingScale }
        return isExpanded ? 1 : Pulse.restingScale
    }

    /// Expanding and contracting differ in length, so the curve is picked
    /// from the value being animated *to* rather than set once.
    private func animation(delay: Double) -> Animation {
        let duration = isExpanded ? Pulse.expandDuration : Pulse.contractDuration
        return .timingCurve(0.42, 0, 0.34, 1, duration: duration).delay(delay)
    }
}

extension PulsingCircles where Center == EmptyView {
    init(isAnimated: Bool = true) {
        self.init(isAnimated: isAnimated) { EmptyView() }
    }
}
