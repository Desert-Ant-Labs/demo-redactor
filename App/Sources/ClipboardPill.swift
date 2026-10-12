import AppKit
import Observation
import SwiftUI

/// The pill that drops in at the top of the screen when a copy holds personal
/// data, with the switch between the redacted text and the user's original.
/// It leaves after a few seconds unless the pointer is on it.
@MainActor
final class ClipboardPill {
    /// Called with true for the redacted text, false for the original.
    var onChoose: (Bool) -> Void = { _ in }

    private let state = PillState()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var isHovering = false

    private static let decisionTime: Duration = .seconds(10)
    private static let confirmationTime: Duration = .milliseconds(1500)
    private static let afterHoverTime: Duration = .seconds(5)

    func show(_ finding: Finding, isRedacted: Bool, isChosen: Bool = false) {
        state.finding = finding
        state.isRedacted = isRedacted
        state.pastedInto = nil
        state.isExpanded = false
        present()
        scheduleDismissal(after: isChosen ? Self.confirmationTime : Self.decisionTime)
    }

    func remind(_ finding: Finding, pastedInto app: String) {
        state.finding = finding
        state.isRedacted = false
        state.pastedInto = app
        state.isExpanded = false
        present()
        scheduleDismissal(after: Self.decisionTime)
    }

    func setRedacted(_ isRedacted: Bool) {
        guard state.finding != nil else { return }
        state.isRedacted = isRedacted
        scheduleDismissal(after: isRedacted ? Self.decisionTime : Self.confirmationTime)
    }

    func hide() {
        dismissal?.cancel()
        guard state.isShown else { return }
        withAnimation(.easeIn(duration: 0.18)) { state.isShown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !state.isShown else { return }
            panel?.orderOut(nil)
            state.finding = nil
        }
    }

    private func present() {
        let panel = panel ?? makePanel()
        self.panel = panel
        // The view picks up the new finding on the next pass, so measure after it.
        Task {
            await Task.yield()
            layout(animated: state.isShown)
            panel.orderFrontRegardless()
            guard !state.isShown else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { state.isShown = true }
        }
    }

    /// Sizes the panel to the pill, centered under the menu bar of the screen
    /// with the pointer. The panel is never bigger than what it draws, so it
    /// never takes a click meant for the window behind.
    private func layout(animated: Bool) {
        guard let panel, let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated)
    }

    private func scheduleDismissal(after delay: Duration) {
        dismissal?.cancel()
        guard !isHovering else { return }
        dismissal = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Glass follows the window's appearance, not the SwiftUI color scheme.
        panel.appearance = NSAppearance(named: .darkAqua)

        let actions = PillActions(
            choose: { [weak self] in self?.onChoose($0) },
            toggleDetails: { [weak self] in self?.toggleDetails() },
            close: { [weak self] in self?.hide() },
            hover: { [weak self] in self?.hover($0) }
        )
        panel.contentView = FirstClickHostingView(rootView: PillView(state: state, actions: actions))
        return panel
    }

    private func toggleDetails() {
        withAnimation(.smooth(duration: 0.25)) { state.isExpanded.toggle() }
        relayout()
    }

    private func relayout() {
        Task {
            await Task.yield()
            layout(animated: true)
        }
    }

    private func hover(_ isInside: Bool) {
        isHovering = isInside
        if isInside {
            dismissal?.cancel()
        } else {
            scheduleDismissal(after: Self.afterHoverTime)
        }
    }
}

@MainActor
@Observable
final class PillState {
    var finding: Finding?
    var isRedacted = true
    /// Set when the pill is a reminder after a paste, to the app's name.
    var pastedInto: String?
    var isExpanded = false
    var isShown = false
}

struct PillActions {
    let choose: (Bool) -> Void
    let toggleDetails: () -> Void
    let close: () -> Void
    let hover: (Bool) -> Void
}
