import AppKit
import CodexAutofocusCore
import Foundation

@MainActor
final class MenuBarModel: ObservableObject {
    struct DisplayStatus {
        var enabled = false
        var registered = false
        var issues: [String] = ["Status has not loaded."]
    }

    @Published private(set) var status = DisplayStatus()
    @Published private(set) var lastErrorMessage: String?

    private let autofocus = CodexAutofocus()

    private var helperPath: String {
        let installedHelper = autofocus.codexHome.appendingPathComponent("bin/codex-autofocus").path
        if FileManager.default.isExecutableFile(atPath: installedHelper) {
            return installedHelper
        }

        if let bundledHelper = Bundle.main.resourceURL?.appendingPathComponent("codex-autofocus").path,
           FileManager.default.isExecutableFile(atPath: bundledHelper) {
            return bundledHelper
        }

        return installedHelper
    }

    var statusTitle: String {
        if !status.registered {
            return "Not Registered"
        }
        return status.enabled ? "Enabled" : "Disabled"
    }

    var statusDetail: String {
        status.registered ? "Stop hook installed" : "Stop hook missing"
    }

    var statusIconName: String {
        if !status.registered {
            return "exclamationmark.circle"
        }
        return status.enabled ? "bolt.circle.fill" : "bolt.slash.circle"
    }

    var shortIssue: String? {
        guard let issue = status.issues.first else { return nil }
        return issue.count <= 30 ? issue : String(issue.prefix(27)) + "..."
    }

    func refresh() {
        do {
            let next = try autofocus.status(binaryPath: helperPath)
            status = DisplayStatus(
                enabled: next.enabled,
                registered: next.registered,
                issues: next.issues
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = String(describing: error)
            status = DisplayStatus(enabled: false, registered: false, issues: ["Status failed."])
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            _ = try autofocus.setEnabled(enabled, binaryPath: helperPath)
            refresh()
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    func registerHook() {
        do {
            _ = try autofocus.install(binaryPath: helperPath)
            refresh()
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    func removeHook() {
        do {
            _ = try autofocus.uninstall(binaryPath: helperPath)
            refresh()
        } catch {
            lastErrorMessage = String(describing: error)
        }
    }

    func revealConfig() {
        reveal(autofocus.configURL)
    }

    func revealHooks() {
        reveal(autofocus.hooksURL)
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
