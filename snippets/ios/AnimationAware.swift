import SwiftUI

/// Pattern for an animation-aware view: only ticks `TimelineView(.animation)`
/// while the state actually warrants per-frame redraws. Idle state draws once.
///
/// In a naive implementation a connection-status dot would call
/// `TimelineView(.animation)` unconditionally and burn CPU repainting an
/// otherwise-identical frame 60 times per second. Gating the timeline on
/// state cuts the redraw cost to zero when nothing is moving, with no
/// behavioural change for the user.
///
/// The same pattern is used for the door-position visualisation and the
/// scanning radar canvas in the bigger app.
struct AnimationAwareDot: View {

    enum State { case idle, connecting, connected, error }

    let state: State
    private let dotSize: CGFloat = 10

    private var isAnimating: Bool {
        switch state {
        case .connected, .connecting: return true
        case .idle, .error: return false
        }
    }

    private var color: Color {
        switch state {
        case .idle:       return .gray
        case .connecting: return .yellow
        case .connected:  return .green
        case .error:      return .red
        }
    }

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation) { timeline in
                    content(t: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                content(t: 0)
            }
        }
    }

    @ViewBuilder
    private func content(t: TimeInterval) -> some View {
        ZStack {
            if state == .connected {
                let pulse = CGFloat((sin(t * 2) + 1) / 2)
                Circle()
                    .stroke(color.opacity(0.35 * (1 - pulse)), lineWidth: 2)
                    .frame(width: dotSize + 10 + pulse * 8, height: dotSize + 10 + pulse * 8)
            }
            Circle()
                .fill(color)
                .opacity(state == .connecting ? (sin(t * 4) > 0 ? 1 : 0.3) : 1)
                .frame(width: dotSize, height: dotSize)
        }
    }
}
