import AppKit
import Observation
import SwiftUI

/// The full-screen warning over a held paste: a red wash and glowing edges on
/// every screen, and the card that asks what to do on the screen with the
/// pointer.
///
/// The panels never activate Redactor, so the app being pasted into stays
/// frontmost and the replayed keystroke lands there.
@MainActor
final class PasteWarning {
    enum Content: Equatable {
        case checking
        case found(Finding)
        case failed(String)
    }

    enum Choice {
        case pasteRedacted, pasteAnyway, cancel
    }

    var onChoice: (Choice) -> Void = { _ in }
    /// Set while a paste is held, including the moment before the overlay
    /// appears.
    private(set) var content: Content?

    private let state = WarningState()
    private var panels: [NSPanel] = []
    /// Bumped on every show and hide, so a delayed step from an older one
    /// can tell it is stale.
    private var generation = 0

    func show(_ content: Content, pastingInto app: String) {
        let wasHeld = self.content != nil
        self.content = content
        generation += 1
        state.app = app
        withAnimation(.smooth(duration: 0.34)) { state.content = content }

        guard !state.isShown else { return }
        guard content == .checking else { return present() }
        guard !wasHeld else { return }

        // Most scans finish in a few milliseconds. Waiting a beat keeps a
        // clean paste from flashing the screen red.
        let current = generation
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard current == generation, self.content != nil else { return }
            present()
        }
    }

    func hide() {
        content = nil
        generation += 1
        guard state.isShown else { return }
        withAnimation(.easeIn(duration: 0.14)) { state.isShown = false }

        let current = generation
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            guard current == generation else { return }
            panels.forEach { $0.orderOut(nil) }
        }
    }

    private func present() {
        let mouse = NSEvent.mouseLocation
        let cardScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let view = WarningOverlay(state: state, showsCard: screen == cardScreen) { [weak self] in
                self?.onChoice($0)
            }
            let panel = Self.makePanel(frame: screen.frame)
            panel.contentView = FirstClickHostingView(rootView: view)
            panel.orderFrontRegardless()
            return panel
        }
        withAnimation(.spring(duration: 0.52, bounce: 0.22)) { state.isShown = true }
    }

    private static func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the menu bar and the Dock, so the edges glow all the way round.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setFrame(frame, display: false)
        return panel
    }
}

/// What every screen's overlay draws, shared so the content can change under
/// them without rebuilding the panels.
@MainActor
@Observable
final class WarningState {
    var content: PasteWarning.Content = .checking
    var app = ""
    var isShown = false
}
