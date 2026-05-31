import CodexAutofocusCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let app = CodexAutofocus()

func printUsage() {
    print("""
    Usage:
      codex-autofocus --hook --managed-by codex-autofocus
      codex-autofocus install [--binary <path>]
      codex-autofocus uninstall [--binary <path>]
      codex-autofocus enable [--binary <path>]
      codex-autofocus disable [--binary <path>]
      codex-autofocus status [--binary <path>]
      codex-autofocus install-app [--app <path>]
      codex-autofocus uninstall-app
      codex-autofocus enable-login-item [--app <path>]
      codex-autofocus disable-login-item
      codex-autofocus login-item-status [--app <path>]

    Codex should call this from a Stop hook in ~/.codex/hooks.json.
    """)
}

func value(after flag: String, in arguments: [String]) -> String? {
    guard let flagIndex = arguments.firstIndex(of: flag), arguments.indices.contains(flagIndex + 1) else {
        return nil
    }
    return arguments[flagIndex + 1]
}

func binaryPath(from arguments: [String]) -> String {
    value(after: "--binary", in: arguments) ?? CommandLine.arguments[0]
}

func appPath(from arguments: [String]) -> String {
    value(after: "--app", in: arguments) ?? app.defaultMenuBarAppPath(binaryPath: binaryPath(from: arguments))
}

func describe(_ command: NotifyCommand?) -> String {
    guard let command else { return "<unset>" }
    return ([command.executable] + command.arguments).joined(separator: " ")
}

do {
    switch arguments.first {
    case "--hook":
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        exit(app.handleHook(inputData: inputData))

    case "install":
        let outcome = try app.install(binaryPath: binaryPath(from: arguments))
        print(outcome.changed ? "codex-autofocus hook registered" : "codex-autofocus hook already registered")
        if let configBackupPath = outcome.configBackupPath {
            print("config backup: \(configBackupPath)")
        }
        if let hooksBackupPath = outcome.hooksBackupPath {
            print("hooks backup: \(hooksBackupPath)")
        }
        print("hook: \(outcome.hookCommand)")

    case "enable":
        _ = try app.setEnabled(true, binaryPath: binaryPath(from: arguments))
        print("codex-autofocus enabled")

    case "disable":
        _ = try app.setEnabled(false, binaryPath: binaryPath(from: arguments))
        print("codex-autofocus disabled")

    case "uninstall":
        let outcome = try app.uninstall(binaryPath: binaryPath(from: arguments))
        if outcome.changed {
            print("codex-autofocus hook removed")
            if let hooksBackupPath = outcome.hooksBackupPath {
                print("hooks backup: \(hooksBackupPath)")
            }
        } else {
            print("codex-autofocus hook was not registered")
        }

    case "status":
        let status = try app.status(binaryPath: binaryPath(from: arguments))
        print(status.enabled ? "enabled" : "disabled")
        print(status.registered ? "registered" : "not registered")
        print("hook: \(status.hookCommand)")
        print("notify: \(describe(status.currentNotify))")
        if !status.issues.isEmpty {
            print("issues:")
            for issue in status.issues {
                print("- \(issue)")
            }
        }

    case "install-app":
        let target = appPath(from: arguments)
        let changed = try app.installAppShortcut(appPath: target)
        print(changed ? "Codex Autofocus app shortcut installed" : "Codex Autofocus app shortcut already installed")
        print("shortcut: \(app.appShortcutURL.path)")
        print("app: \(target)")

    case "uninstall-app":
        let changed = try app.uninstallAppShortcut()
        print(changed ? "Codex Autofocus app shortcut removed" : "Codex Autofocus app shortcut was not installed")

    case "enable-login-item":
        let target = appPath(from: arguments)
        let changed = try app.setLaunchAtLogin(true, appPath: target)
        print(changed ? "Codex Autofocus will open at login" : "Codex Autofocus was already set to open at login")
        print("launch agent: \(app.loginAgentURL.path)")
        print("app: \(target)")

    case "disable-login-item":
        let changed = try app.setLaunchAtLogin(false, appPath: appPath(from: arguments))
        print(changed ? "Codex Autofocus will not open at login" : "Codex Autofocus login item was not installed")

    case "login-item-status":
        let target = appPath(from: arguments)
        print(app.loginItemStatus(appPath: target) ? "enabled" : "disabled")
        print("launch agent: \(app.loginAgentURL.path)")
        print("app: \(target)")

    case "-h", "--help", nil:
        printUsage()

    default:
        printUsage()
        exit(64)
    }
} catch {
    fputs("codex-autofocus: \(error)\n", stderr)
    exit(1)
}
