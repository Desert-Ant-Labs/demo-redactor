import SwiftUI

/// The system glass button dims in a window that isn't key, and the pill and
/// the menu never are, so this draws the same glass itself.
struct GlassCapsuleButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.cream)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            // Glass alone washes a tint out to grey, so the color sits under it.
            .background(tint, in: .capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
