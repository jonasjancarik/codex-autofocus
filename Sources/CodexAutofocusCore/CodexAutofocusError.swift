import Foundation

public enum CodexAutofocusError: Error, CustomStringConvertible, Sendable {
    case appShortcutExists(String)
    case invalidNotifyValue(String)
    case missingMenuBarApp(String)
    case missingHomeDirectory
    case missingManagedHook
    case commandFailed(executable: String, status: Int32)

    public var description: String {
        switch self {
        case .appShortcutExists(let path):
            return "A file already exists at \(path). Remove it first if you want Codex Autofocus to create an app shortcut there."
        case .invalidNotifyValue(let message):
            return "Invalid Codex notify value: \(message)"
        case .missingMenuBarApp(let path):
            return "Codex Autofocus menu bar app was not found at \(path)"
        case .missingHomeDirectory:
            return "Could not resolve the current user's home directory"
        case .missingManagedHook:
            return "Codex Autofocus hook is not installed"
        case .commandFailed(let executable, let status):
            return "Command failed with status \(status): \(executable)"
        }
    }
}
