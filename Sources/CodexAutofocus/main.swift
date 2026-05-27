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

    Codex should call this from a Stop hook in ~/.codex/hooks.json.
    """)
}

func binaryPath(from arguments: [String]) -> String {
    guard let flagIndex = arguments.firstIndex(of: "--binary"), arguments.indices.contains(flagIndex + 1) else {
        return CommandLine.arguments[0]
    }
    return arguments[flagIndex + 1]
}

func describe(_ command: NotifyCommand?) -> String {
    guard let command else { return "<unset>" }
    return ([command.executable] + command.arguments).joined(separator: " ")
}

do {
    switch arguments.first {
    case "--hook":
        exit(app.handleHook())

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
