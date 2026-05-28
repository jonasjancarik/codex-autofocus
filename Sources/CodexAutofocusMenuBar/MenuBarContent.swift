import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        Group {
            Text(model.statusSummary)
                .foregroundStyle(.secondary)

            if let issue = model.shortIssue {
                Text(issue)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(model.status.enabled ? "Turn Autofocus Off" : "Turn Autofocus On") {
                model.setEnabled(!model.status.enabled)
            }
            .disabled(!model.status.registered)

            Menu("Advanced") {
                Button(model.status.registered ? "Repair Codex Hook" : "Install Codex Hook") {
                    model.registerHook()
                }

                Button("Trust Installed Hook...") {
                    model.trustInstalledHook()
                }
                .disabled(!model.status.registered)

                Button("Remove Codex Hook...") {
                    model.removeHook()
                }
                .disabled(!model.status.registered)

                Divider()

                Button("Show config.toml") {
                    model.revealConfig()
                }

                Button("Show hooks.json") {
                    model.revealHooks()
                }
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

            Button("Quit Codex Autofocus") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
