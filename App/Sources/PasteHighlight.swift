import AppKit
import Observation
import SwiftUI

/// A clay red underline that draws in under each value just pasted, holds
/// for a moment, and fades. Any keystroke, click, or scroll clears it early,
/// because the text under it may have moved.
@MainActor
final class PasteHighlight {
    private var panels: [NSPanel] = []
    private var state = HighlightState()
    private var monitor: Any?
    private var fading: Task<Void, Never>?

    func flash(_ rects: [CGRect]) {
        clear()
        guard !rects.isEmpty else { return }

        let state = HighlightState()
        self.state = state
        panels = rects.map { rect in
            let panel = Self.makePanel(frame: rect.insetBy(dx: -3, dy: -2))
            panel.contentView = NSHostingView(rootView: HighlightMark(state: state))
            panel.orderFrontRegardless()
            return panel
        }
        withAnimation(.smooth(duration: 0.4)) { state.isShown = true }

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        }
        fading = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            clear()
        }
    }

    func clear() {
        fading?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard !panels.isEmpty else { return }

        let leaving = panels
        panels = []
        withAnimation(.easeIn(duration: 0.25)) { state.isShown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            leaving.forEach { $0.orderOut(nil) }
        }
    }

    private static func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Only a mark: every click goes to the app underneath.
        panel.ignoresMouseEvents = true
        return panel
    }
}

@MainActor
@Observable
final class HighlightState {
    var isShown = false
}

private struct HighlightMark: View {
    let state: HighlightState

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clayRed.opacity(0.12))
                .opacity(state.isShown ? 1 : 0)
            Capsule()
                .fill(Color.clayRed)
                .frame(height: 2.5)
                .shadow(color: .clayRed.opacity(0.8), radius: 3)
                .scaleEffect(x: state.isShown ? 1 : 0, anchor: .leading)
        }
    }
}

#Preview("Underline") {
    @Previewable @State var state = HighlightState()
    Text("anna@example.hu")
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background { HighlightMark(state: state) }
        .padding(40)
        .onAppear { withAnimation(.smooth(duration: 0.4).delay(0.3)) { state.isShown = true } }
}
