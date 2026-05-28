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
    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

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

    var statusSummary: String {
        if !status.registered {
            return "Not Registered"
        }
        let behavior = status.enabled ? "On" : "Off"
        return "\(behavior) · Hook installed"
    }

    var statusIconName: String {
        if !status.registered {
            return "exclamationmark.circle"
        }
        return status.enabled ? "bolt.circle.fill" : "bolt.slash.circle"
    }

    var shortIssue: String? {
        guard let issue = status.issues.first else { return nil }
        if issue == "Managed Stop hook is not registered." {
            return "Hook not installed"
        }
        if issue == "Legacy notify wrapper is still installed." {
            return "Legacy notify cleanup needed"
        }
        if issue == "Managed Stop hook is registered but may need Codex hook review before it runs." {
            return "Approve hook in Codex"
        }
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

    func trustInstalledHook() {
        guard confirmTrustInstalledHook() else { return }
        do {
            _ = try autofocus.trustInstalledHook(binaryPath: helperPath)
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

    private func confirmTrustInstalledHook() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Trust Installed Hook?"
        alert.informativeText = "This writes Codex's hook trust record directly to config.toml and bypasses Codex's normal hook review prompt. Only continue if you trust the installed Codex Autofocus hook."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Trust Hook")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
