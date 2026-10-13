import AppKit
import Sparkle
import SwiftUI

/// Sparkle, started once at launch.
@MainActor
final class Updates {
    static let shared = Updates()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var updater: SPUUpdater { controller.updater }

    /// Activated first, or the update window opens behind the frontmost app.
    func check() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

struct AutomaticUpdatesToggle: View {
    @State private var isOn = Updates.shared.updater.automaticallyChecksForUpdates

    var body: some View {
        Toggle("Check for updates automatically", isOn: $isOn)
            .onChange(of: isOn) { Updates.shared.updater.automaticallyChecksForUpdates = isOn }
    }
}
