import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        Group {
            Text(model.statusTitle)
            Text(model.statusDetail)
                .foregroundStyle(.secondary)

            if let issue = model.shortIssue {
                Text(issue)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(model.status.enabled ? "Disable" : "Enable") {
                model.setEnabled(!model.status.enabled)
            }
            .disabled(!model.status.registered)

            Button(model.status.registered ? "Register Again" : "Register Hook") {
                model.registerHook()
            }

            Button("Remove Hook") {
                model.removeHook()
            }
            .disabled(!model.status.registered)

            Divider()

            Button("Refresh") {
                model.refresh()
            }

            Button("Reveal Config") {
                model.revealConfig()
            }

            Button("Reveal Hooks") {
                model.revealHooks()
            }

            if let message = model.lastErrorMessage {
                Divider()
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Copy Error") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
