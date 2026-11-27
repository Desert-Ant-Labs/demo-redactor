import DesertAnt
import SwiftUI

@main
struct RedactorApp: App {
    @State private var model: RedactorModel

    init() {
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "DAL_API_KEY") as? String, !apiKey.isEmpty {
            DesertAnt.configure(apiKey: apiKey)
        }
        _model = State(initialValue: RedactorModel())
        _ = Updates.shared
    }

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
