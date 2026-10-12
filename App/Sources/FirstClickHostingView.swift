import AppKit
import SwiftUI

/// Redactor's panels are never key, so without this the first click on a
/// button would only focus the panel.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
