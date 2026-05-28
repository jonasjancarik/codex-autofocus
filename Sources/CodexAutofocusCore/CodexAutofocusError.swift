import Foundation

public enum CodexAutofocusError: Error, CustomStringConvertible, Sendable {
    case invalidNotifyValue(String)
    case missingHomeDirectory
    case missingManagedHook
    case commandFailed(executable: String, status: Int32)

    public var description: String {
        switch self {
        case .invalidNotifyValue(let message):
            return "Invalid Codex notify value: \(message)"
        case .missingHomeDirectory:
            return "Could not resolve the current user's home directory"
        case .missingManagedHook:
            return "Codex Autofocus hook is not installed"
        case .commandFailed(let executable, let status):
            return "Command failed with status \(status): \(executable)"
        }
    }
}
