import CryptoKit
import Foundation

public struct CodexAutofocus: Sendable {
    public struct InstallOutcome: Sendable {
        public var changed: Bool
        public var configBackupPath: String?
        public var hooksBackupPath: String?
        public var hookCommand: String
    }

    public struct Status: Sendable {
        public var enabled: Bool
        public var registered: Bool
        public var currentNotify: NotifyCommand?
        public var hookCommand: String
        public var issues: [String]
    }

    public struct TrustOutcome: Sendable {
        public var changed: Bool
        public var configBackupPath: String?
        public var trustedHash: String
        public var hookStateKeys: [String]
    }

    public struct State: Codable, Sendable {
        public var enabled: Bool
        public var installedAt: String?
        public var hookCommand: String?
        public var previousNotify: NotifyCommand?
        public var installedNotify: NotifyCommand?

        public init(
            enabled: Bool = true,
            installedAt: String? = nil,
            hookCommand: String? = nil,
            previousNotify: NotifyCommand? = nil,
            installedNotify: NotifyCommand? = nil
        ) {
            self.enabled = enabled
            self.installedAt = installedAt
            self.hookCommand = hookCommand
            self.previousNotify = previousNotify
            self.installedNotify = installedNotify
        }

        enum CodingKeys: String, CodingKey {
            case enabled
            case installedAt
            case hookCommand
            case previousNotify
            case installedNotify
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            installedAt = try container.decodeIfPresent(String.self, forKey: .installedAt)
            hookCommand = try container.decodeIfPresent(String.self, forKey: .hookCommand)
            previousNotify = try container.decodeIfPresent(NotifyCommand.self, forKey: .previousNotify)
            installedNotify = try container.decodeIfPresent(NotifyCommand.self, forKey: .installedNotify)
        }
    }

    public static let managedMarker = "--managed-by codex-autofocus"
    public static let hookStatusMessage = "Codex Autofocus is bringing Codex forward"
    public static let loginAgentLabel = "com.jonasjancarik.codex-autofocus"

    public var homeDirectory: URL
    public var codexBundleIdentifier: String

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        codexBundleIdentifier: String = "com.openai.codex"
    ) {
        self.homeDirectory = homeDirectory
        self.codexBundleIdentifier = codexBundleIdentifier
    }

    public var codexHome: URL {
        homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    public var configURL: URL {
        codexHome.appendingPathComponent("config.toml")
    }

    public var hooksURL: URL {
        codexHome.appendingPathComponent("hooks.json")
    }

    public var stateURL: URL {
        codexHome
            .appendingPathComponent("codex-autofocus", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    public var debugLogURL: URL {
        stateURL.deletingLastPathComponent().appendingPathComponent("debug.log")
    }

    public var userApplicationsURL: URL {
        homeDirectory.appendingPathComponent("Applications", isDirectory: true)
    }

    public var appShortcutURL: URL {
        userApplicationsURL.appendingPathComponent("Codex Autofocus.app")
    }

    public var launchAgentsURL: URL {
        homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    public var loginAgentURL: URL {
        launchAgentsURL.appendingPathComponent("\(Self.loginAgentLabel).plist")
    }

    public var defaultComputerUseNotify: NotifyCommand {
        NotifyCommand(
            executable: codexHome
                .appendingPathComponent("computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient")
                .path,
            arguments: ["turn-ended"]
        )
    }

    public func installedNotify(binaryPath: String) -> NotifyCommand {
        NotifyCommand(executable: binaryPath, arguments: ["turn-ended"])
    }

    public func defaultMenuBarAppPath(binaryPath: String) -> String {
        if binaryPath == "/opt/homebrew/bin/codex-autofocus" {
            return "/opt/homebrew/opt/codex-autofocus/Codex Autofocus.app"
        }
        if binaryPath == "/usr/local/bin/codex-autofocus" {
            return "/usr/local/opt/codex-autofocus/Codex Autofocus.app"
        }

        let binaryURL = URL(fileURLWithPath: binaryPath)
        let directory = binaryURL.deletingLastPathComponent()

        if directory.lastPathComponent == "Resources",
           directory.deletingLastPathComponent().lastPathComponent == "Contents"
        {
            return directory
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
        }

        return directory
            .deletingLastPathComponent()
            .appendingPathComponent("Codex Autofocus.app")
            .path
    }

    public func managedHookCommand(binaryPath: String) -> String {
        "\(quoteCommandPath(binaryPath)) --hook \(Self.managedMarker)"
    }

    public func handleHook(inputData: Data = Data()) -> Int32 {
        let state = (try? readState()) ?? State(enabled: true)
        let hookID = UUID().uuidString
        appendDebugLog("hook_id=\(hookID) hook received enabled=\(state.enabled) \(hookDebugSummary(inputData: inputData))")

        guard state.enabled else {
            appendDebugLog("hook_id=\(hookID) autofocus skipped reason=disabled")
            return 0
        }

        if shouldSkipAutofocus(inputData: inputData) {
            appendDebugLog("hook_id=\(hookID) autofocus skipped reason=ephemeral_session")
            return 0
        }

        appendDebugLog("hook_id=\(hookID) focus starting")
        let status = runProcess(executable: "/usr/bin/open", arguments: ["-b", codexBundleIdentifier])
        appendDebugLog("hook_id=\(hookID) focus open_exit=\(status)")
        return status
    }

    public func install(binaryPath: String) throws -> InstallOutcome {
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let hookCommand = managedHookCommand(binaryPath: binaryPath)
        let existingState = (try? readState()) ?? State(enabled: true)
        let configBackup = try cleanUpLegacyNotify(binaryPath: binaryPath, state: existingState)

        var hooksDocument = try loadHooksDocument()
        hooksDocument.upsertManagedStopHook(
            command: hookCommand,
            marker: Self.managedMarker,
            timeout: 30,
            statusMessage: Self.hookStatusMessage
        )
        let hooksBackup = try writeHooksDocument(hooksDocument)

        let state = State(
            enabled: existingState.enabled,
            installedAt: ISO8601DateFormatter().string(from: Date()),
            hookCommand: hookCommand
        )
        try writeState(state)

        return InstallOutcome(
            changed: configBackup != nil || hooksBackup != nil,
            configBackupPath: configBackup?.path,
            hooksBackupPath: hooksBackup?.path,
            hookCommand: hookCommand
        )
    }

    public func uninstall(binaryPath: String) throws -> InstallOutcome {
        let hookCommand = managedHookCommand(binaryPath: binaryPath)
        var hooksDocument = try loadHooksDocument()
        let removed = hooksDocument.removeManagedHooks(marker: Self.managedMarker)
        let hooksBackup = removed ? try writeHooksDocument(hooksDocument) : nil

        var state = (try? readState()) ?? State(enabled: false)
        state.enabled = false
        state.hookCommand = hookCommand
        try writeState(state)

        return InstallOutcome(
            changed: removed,
            configBackupPath: nil,
            hooksBackupPath: hooksBackup?.path,
            hookCommand: hookCommand
        )
    }

    public func setEnabled(_ enabled: Bool, binaryPath: String) throws -> State {
        var state = (try? readState()) ?? State(enabled: enabled)
        state.enabled = enabled
        state.hookCommand = managedHookCommand(binaryPath: binaryPath)
        try writeState(state)
        return state
    }

    public func installAppShortcut(appPath: String) throws -> Bool {
        let appURL = URL(fileURLWithPath: appPath)
        try validateMenuBarApp(at: appURL)
        try FileManager.default.createDirectory(at: userApplicationsURL, withIntermediateDirectories: true)

        if let existingDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: appShortcutURL.path) {
            if existingDestination == appURL.path {
                return false
            }
            try FileManager.default.removeItem(at: appShortcutURL)
        } else if FileManager.default.fileExists(atPath: appShortcutURL.path) {
            throw CodexAutofocusError.appShortcutExists(appShortcutURL.path)
        }

        try FileManager.default.createSymbolicLink(at: appShortcutURL, withDestinationURL: appURL)
        return true
    }

    public func uninstallAppShortcut() throws -> Bool {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: appShortcutURL.path)) != nil {
            try FileManager.default.removeItem(at: appShortcutURL)
            return true
        }
        if FileManager.default.fileExists(atPath: appShortcutURL.path) {
            throw CodexAutofocusError.appShortcutExists(appShortcutURL.path)
        }
        return false
    }

    public func appShortcutStatus(appPath: String) -> Bool {
        guard let existingDestination = try? FileManager.default.destinationOfSymbolicLink(atPath: appShortcutURL.path) else {
            return false
        }
        return existingDestination == URL(fileURLWithPath: appPath).path
    }

    public func setLaunchAtLogin(_ enabled: Bool, appPath: String) throws -> Bool {
        if enabled {
            return try installLoginAgent(appPath: appPath)
        }
        return try uninstallLoginAgent()
    }

    public func loginItemStatus(appPath: String) -> Bool {
        guard
            let data = try? Data(contentsOf: loginAgentURL),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = object as? [String: Any],
            let arguments = dictionary["ProgramArguments"] as? [String]
        else {
            return false
        }

        return arguments == ["/usr/bin/open", URL(fileURLWithPath: appPath).path]
    }

    public func trustInstalledHook(binaryPath: String) throws -> TrustOutcome {
        let hookCommand = managedHookCommand(binaryPath: binaryPath)
        let hooksDocument = try loadHooksDocument()
        let hookLocations = hooksDocument.managedStopHookLocations(marker: Self.managedMarker)
        guard !hookLocations.isEmpty else {
            throw CodexAutofocusError.missingManagedHook
        }

        let trustedHash = managedStopHookTrustedHash(command: hookCommand)
        let hookStateKeys = hookLocations.map { hookStateKey(forStopHookAt: $0) }
        let existingText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        var nextText = existingText

        for key in hookStateKeys {
            let document = CodexConfigDocument(text: nextText)
            guard document.trustedHash(forHookStateKey: key) != trustedHash else { continue }
            nextText = document.settingTrustedHash(trustedHash, forHookStateKey: key)
        }

        let backupURL: URL?
        if nextText != existingText {
            backupURL = FileManager.default.fileExists(atPath: configURL.path)
                ? try backupFile(configURL, label: "config.trust")
                : nil
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try nextText.write(to: configURL, atomically: true, encoding: .utf8)
        } else {
            backupURL = nil
        }

        return TrustOutcome(
            changed: nextText != existingText,
            configBackupPath: backupURL?.path,
            trustedHash: trustedHash,
            hookStateKeys: hookStateKeys
        )
    }

    public func status(binaryPath: String) throws -> Status {
        let hookCommand = managedHookCommand(binaryPath: binaryPath)
        let state = try? readState()
        let hooksDocument = try loadHooksDocument()
        let hookLocations = hooksDocument.managedStopHookLocations(marker: Self.managedMarker)
        let registered = !hookLocations.isEmpty
        let text = try String(contentsOf: configURL, encoding: .utf8)
        let currentNotify = try CodexConfigDocument(text: text).topLevelNotify()

        var issues: [String] = []
        if !registered {
            issues.append("Managed Stop hook is not registered.")
        }
        if currentNotify == installedNotify(binaryPath: binaryPath) {
            issues.append("Legacy notify wrapper is still installed.")
        }
        if registered && !hasTrustState(for: hookLocations, hookCommand: hookCommand, configText: text) {
            issues.append("Managed Stop hook is registered but may need Codex hook review before it runs.")
        }

        return Status(
            enabled: state?.enabled ?? registered,
            registered: registered,
            currentNotify: currentNotify,
            hookCommand: hookCommand,
            issues: issues
        )
    }

    private func hasTrustState(
        for hookLocations: [(groupIndex: Int, hookIndex: Int)],
        hookCommand: String,
        configText: String
    ) -> Bool {
        let trustedHash = managedStopHookTrustedHash(command: hookCommand)
        let document = CodexConfigDocument(text: configText)
        return hookLocations.contains { location in
            document.trustedHash(forHookStateKey: hookStateKey(forStopHookAt: location)) == trustedHash
        }
    }

    private func hookStateKey(forStopHookAt location: (groupIndex: Int, hookIndex: Int)) -> String {
        "\(hooksURL.path):stop:\(location.groupIndex):\(location.hookIndex)"
    }

    private func managedStopHookTrustedHash(command: String) -> String {
        let identity: [String: Any] = [
            "event_name": "stop",
            "hooks": [[
                "async": false,
                "command": command,
                "statusMessage": Self.hookStatusMessage,
                "timeout": 30,
                "type": "command",
            ]],
        ]
        let data = (try? JSONSerialization.data(
            withJSONObject: identity,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }

    private func cleanUpLegacyNotify(binaryPath: String, state: State) throws -> URL? {
        let existingText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let document = CodexConfigDocument(text: existingText)
        let currentNotify = try document.topLevelNotify()
        let installed = installedNotify(binaryPath: binaryPath)

        var nextText = document.settingFeature("hooks", to: true)
        if currentNotify == installed {
            if let previousNotify = state.previousNotify ?? fallbackNotifyForCleanup() {
                nextText = CodexConfigDocument(text: nextText).replacingTopLevelNotify(with: previousNotify)
            } else {
                nextText = CodexConfigDocument(text: nextText).removingTopLevelNotify()
            }
        }

        guard nextText != existingText else { return nil }
        let backupURL = try backupFile(configURL, label: "config")
        try nextText.write(to: configURL, atomically: true, encoding: .utf8)
        return backupURL
    }

    private func fallbackNotifyForCleanup() -> NotifyCommand? {
        FileManager.default.isExecutableFile(atPath: defaultComputerUseNotify.executable)
            ? defaultComputerUseNotify
            : nil
    }

    private func installLoginAgent(appPath: String) throws -> Bool {
        let appURL = URL(fileURLWithPath: appPath)
        try validateMenuBarApp(at: appURL)
        if loginItemStatus(appPath: appURL.path) {
            return false
        }

        try FileManager.default.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
        let data = try loginAgentData(appPath: appURL.path)
        try data.write(to: loginAgentURL, options: .atomic)
        return true
    }

    private func uninstallLoginAgent() throws -> Bool {
        guard FileManager.default.fileExists(atPath: loginAgentURL.path) else {
            return false
        }

        try FileManager.default.removeItem(at: loginAgentURL)
        return true
    }

    private func loginAgentData(appPath: String) throws -> Data {
        let propertyList: [String: Any] = [
            "Label": Self.loginAgentLabel,
            "LimitLoadToSessionType": "Aqua",
            "ProgramArguments": ["/usr/bin/open", appPath],
            "RunAtLoad": true,
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
    }

    private func validateMenuBarApp(at appURL: URL) throws {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw CodexAutofocusError.missingMenuBarApp(appURL.path)
        }
    }

    private func loadHooksDocument() throws -> CodexHooksDocument {
        guard FileManager.default.fileExists(atPath: hooksURL.path) else {
            return CodexHooksDocument()
        }

        do {
            return try CodexHooksDocument(data: Data(contentsOf: hooksURL))
        } catch {
            _ = try? backupFile(hooksURL, label: "hooks.corrupt")
            return CodexHooksDocument()
        }
    }

    private func writeHooksDocument(_ hooksDocument: CodexHooksDocument) throws -> URL? {
        let backupURL = FileManager.default.fileExists(atPath: hooksURL.path)
            ? try backupFile(hooksURL, label: "hooks")
            : nil
        try FileManager.default.createDirectory(at: hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try hooksDocument.data().write(to: hooksURL, options: .atomic)
        return backupURL
    }

    private func backupFile(_ url: URL, label: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let fileManager = FileManager.default
        var backupURL = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).bak-\(stamp)-codex-autofocus-\(label)")
        var suffix = 1

        while fileManager.fileExists(atPath: backupURL.path) {
            backupURL = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).bak-\(stamp)-codex-autofocus-\(label)-\(suffix)")
            suffix += 1
        }

        try FileManager.default.copyItem(at: url, to: backupURL)
        return backupURL
    }

    private func writeState(_ state: State) throws {
        let directory = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettySorted.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }

    private func readState() throws -> State {
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(State.self, from: data)
    }

    func hookDebugSummary(inputData: Data) -> String {
        var parts = ["payload_bytes=\(inputData.count)"]
        guard !inputData.isEmpty else {
            parts.append("payload=empty")
            return parts.joined(separator: " ")
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: inputData),
            let dictionary = object as? [String: Any]
        else {
            parts.append("payload=unparsed")
            return parts.joined(separator: " ")
        }

        parts.append("payload=json")
        for key in [
            "hook_event_name",
            "event_name",
            "thread_id",
            "turn_id",
            "session_id",
            "source",
            "agent_type",
            "transcript_path",
            "agent_transcript_path",
            "permission_mode",
        ] {
            if let value = dictionary[key] {
                parts.append("\(key)=\(logValue(value))")
            }
        }

        let redactedKeys: Set<String> = ["prompt", "last_assistant_message"]
        let keys = dictionary.keys
            .filter { !redactedKeys.contains($0) }
            .sorted()
            .joined(separator: ",")
        parts.append("payload_keys=\(shellScalar(keys))")
        return parts.joined(separator: " ")
    }

    private func shouldSkipAutofocus(inputData: Data) -> Bool {
        guard
            !inputData.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: inputData),
            let dictionary = object as? [String: Any],
            let transcriptPath = dictionary["transcript_path"]
        else {
            return false
        }

        if transcriptPath is NSNull {
            return true
        }

        if let string = transcriptPath as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed == "<null>"
        }

        return false
    }

    private func runProcess(executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 127
        }
    }

    private func quoteCommandPath(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appendDebugLog(_ message: String) {
        do {
            try FileManager.default.createDirectory(at: debugLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let line = "\(Self.iso8601UTC(Date())) \(message)\n"
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: debugLogURL.path) {
                let handle = try FileHandle(forWritingTo: debugLogURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: debugLogURL, options: .atomic)
            }
        } catch {
            // Hook logging must never prevent Codex from finishing its turn.
        }
    }

    private func logValue(_ value: Any) -> String {
        if let string = value as? String {
            return shellScalar(string)
        }
        if let number = value as? NSNumber {
            return shellScalar(number.stringValue)
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
           let string = String(data: data, encoding: .utf8)
        {
            return shellScalar(string)
        }
        return shellScalar(String(describing: value))
    }

    private func shellScalar(_ value: String) -> String {
        quoteCommandPath(value.replacingOccurrences(of: "\n", with: "\\n"))
    }

    private static func iso8601UTC(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private extension JSONEncoder {
    static var prettySorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
