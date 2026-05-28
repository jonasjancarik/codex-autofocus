import SwiftUI

@main
struct CodexAutofocusMenuBarApp: App {
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
                .onAppear { model.refresh() }
        } label: {
            Image(systemName: model.statusIconName)
                .accessibilityLabel("Codex Autofocus")
        }
        .menuBarExtraStyle(.menu)
    }
}
