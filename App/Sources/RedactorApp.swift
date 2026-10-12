import SwiftUI

@main
struct RedactorApp: App {
    @State private var model = RedactorModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(model.menuImage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
