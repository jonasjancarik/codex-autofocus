import XCTest
@testable import CodexAutofocusCore

final class CodexConfigDocumentTests: XCTestCase {
    func testInstallMigratesLegacyNotifyAndRegistersStopHook() throws {
        let fixture = try makeFixture()
        let previousNotify = NotifyCommand(executable: "/tmp/original-notifier", arguments: ["turn-ended"])
        let legacyState = CodexAutofocus.State(
            enabled: true,
            installedAt: "2026-05-27T20:00:00Z",
            previousNotify: previousNotify,
            installedNotify: NotifyCommand(executable: fixture.binaryPath, arguments: ["turn-ended"])
        )
        try writeState(legacyState, app: fixture.app)
        try #"""
        model = "gpt-5.5"
        notify = ["__BINARY__", "turn-ended"]

        [features]
        multi_agent = true
        """#.replacingOccurrences(of: "__BINARY__", with: fixture.binaryPath)
            .write(to: fixture.app.configURL, atomically: true, encoding: .utf8)
        try #"""
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/loopndroll-hook' --hook --managed-by loopndroll"
                  }
                ]
              }
            ]
          }
        }
        """#.write(to: fixture.app.hooksURL, atomically: true, encoding: .utf8)

        let outcome = try fixture.app.install(binaryPath: fixture.binaryPath)

        XCTAssertTrue(outcome.changed)
        let config = try String(contentsOf: fixture.app.configURL, encoding: .utf8)
        XCTAssertTrue(config.contains(previousNotify.tomlArray))
        XCTAssertTrue(config.contains("hooks = true"))
        XCTAssertFalse(config.contains(#"notify = ["# + fixture.binaryPath))

        let hooks = try String(contentsOf: fixture.app.hooksURL, encoding: .utf8)
        XCTAssertTrue(hooks.contains("--managed-by loopndroll"))
        XCTAssertTrue(hooks.contains(CodexAutofocus.managedMarker))
    }

    func testDisableEnableOnlyChangesRuntimeState() throws {
        let fixture = try makeFixture()
        try "model = \"gpt-5.5\"\n".write(to: fixture.app.configURL, atomically: true, encoding: .utf8)
        _ = try fixture.app.install(binaryPath: fixture.binaryPath)
        let configBefore = try String(contentsOf: fixture.app.configURL, encoding: .utf8)
        let hooksBefore = try String(contentsOf: fixture.app.hooksURL, encoding: .utf8)

        _ = try fixture.app.setEnabled(false, binaryPath: fixture.binaryPath)
        var status = try fixture.app.status(binaryPath: fixture.binaryPath)
        XCTAssertFalse(status.enabled)
        XCTAssertTrue(status.registered)
        XCTAssertEqual(configBefore, try String(contentsOf: fixture.app.configURL, encoding: .utf8))
        XCTAssertEqual(hooksBefore, try String(contentsOf: fixture.app.hooksURL, encoding: .utf8))

        _ = try fixture.app.setEnabled(true, binaryPath: fixture.binaryPath)
        status = try fixture.app.status(binaryPath: fixture.binaryPath)
        XCTAssertTrue(status.enabled)
        XCTAssertTrue(status.registered)
    }

    func testUninstallRemovesOnlyManagedHook() throws {
        let fixture = try makeFixture()
        try "model = \"gpt-5.5\"\n".write(to: fixture.app.configURL, atomically: true, encoding: .utf8)
        _ = try fixture.app.install(binaryPath: fixture.binaryPath)

        let outcome = try fixture.app.uninstall(binaryPath: fixture.binaryPath)

        XCTAssertTrue(outcome.changed)
        let hooks = try String(contentsOf: fixture.app.hooksURL, encoding: .utf8)
        XCTAssertFalse(hooks.contains(CodexAutofocus.managedMarker))
    }

    func testTrustInstalledHookWritesCodexTrustedHash() throws {
        let fixture = try makeFixture(binaryPath: "/tmp/codex-autofocus")
        try "model = \"gpt-5.5\"\n".write(to: fixture.app.configURL, atomically: true, encoding: .utf8)
        _ = try fixture.app.install(binaryPath: fixture.binaryPath)

        var status = try fixture.app.status(binaryPath: fixture.binaryPath)
        XCTAssertTrue(status.issues.contains("Managed Stop hook is registered but may need Codex hook review before it runs."))

        let outcome = try fixture.app.trustInstalledHook(binaryPath: fixture.binaryPath)

        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.trustedHash, "sha256:7badca2bdb8f56873959bbdeeb8a4c3a66f3788686236eafcd820d8e65b09066")
        XCTAssertEqual(outcome.hookStateKeys, [fixture.app.hooksURL.path + ":stop:0:0"])

        let config = try String(contentsOf: fixture.app.configURL, encoding: .utf8)
        XCTAssertTrue(config.contains("[hooks.state.\"" + fixture.app.hooksURL.path + ":stop:0:0\"]"))
        XCTAssertTrue(config.contains("trusted_hash = \"sha256:7badca2bdb8f56873959bbdeeb8a4c3a66f3788686236eafcd820d8e65b09066\""))

        status = try fixture.app.status(binaryPath: fixture.binaryPath)
        XCTAssertFalse(status.issues.contains("Managed Stop hook is registered but may need Codex hook review before it runs."))
    }

    func testTrustInstalledHookIsNoopWhenAlreadyTrusted() throws {
        let fixture = try makeFixture(binaryPath: "/tmp/codex-autofocus")
        try "model = \"gpt-5.5\"\n".write(to: fixture.app.configURL, atomically: true, encoding: .utf8)
        _ = try fixture.app.install(binaryPath: fixture.binaryPath)
        _ = try fixture.app.trustInstalledHook(binaryPath: fixture.binaryPath)

        let outcome = try fixture.app.trustInstalledHook(binaryPath: fixture.binaryPath)

        XCTAssertFalse(outcome.changed)
    }

    func testReadsTopLevelNotify() throws {
        let document = CodexConfigDocument(text: #"""
        model = "gpt-5.5"
        notify = ["/tmp/notifier", "turn-ended"]

        [desktop]
        notifications-turn-mode = "always"
        """#)

        XCTAssertEqual(
            try document.topLevelNotify(),
            NotifyCommand(executable: "/tmp/notifier", arguments: ["turn-ended"])
        )
    }

    func testReplacesOnlyTopLevelNotify() {
        let document = CodexConfigDocument(text: #"""
        notify = ["/tmp/old", "turn-ended"]

        [nested]
        notify = ["/tmp/keep", "turn-ended"]
        """#)

        let updated = document.replacingTopLevelNotify(
            with: NotifyCommand(executable: "/tmp/new", arguments: ["turn-ended"])
        )

        XCTAssertTrue(updated.contains(#"notify = ["/tmp/new", "turn-ended"]"#))
        XCTAssertTrue(updated.contains(#"notify = ["/tmp/keep", "turn-ended"]"#))
    }

    func testInsertsNotifyAfterSandboxModeWhenMissing() {
        let document = CodexConfigDocument(text: #"""
        model = "gpt-5.5"
        sandbox_mode = "workspace-write"

        [projects."/tmp"]
        trust_level = "trusted"
        """#)

        let updated = document.replacingTopLevelNotify(
            with: NotifyCommand(executable: "/tmp/new", arguments: ["turn-ended"])
        )

        XCTAssertTrue(updated.contains(#"""
        sandbox_mode = "workspace-write"
        notify = ["/tmp/new", "turn-ended"]
        """#))
    }

    func testTomlEscapingRoundTrips() throws {
        let command = NotifyCommand(executable: #"/tmp/quoted " path"#, arguments: ["turn-ended", "line\nbreak"])

        XCTAssertEqual(try NotifyCommand.fromTomlArray(command.tomlArray), command)
    }

    func testHookTrustedHashRoundTrips() {
        let document = CodexConfigDocument(text: "model = \"gpt-5.5\"\n")
        let key = #"/tmp/codex/hooks.json:stop:1:0"#
        let updated = document.settingTrustedHash("sha256:abc123", forHookStateKey: key)

        XCTAssertEqual(CodexConfigDocument(text: updated).trustedHash(forHookStateKey: key), "sha256:abc123")
    }

    func testHookDebugSummaryRedactsPromptContent() throws {
        let app = CodexAutofocus(homeDirectory: URL(fileURLWithPath: "/tmp/codex-autofocus-tests"))
        let payload = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop",
            "thread_id": "thread-1",
            "turn_id": "turn-1",
            "source": "vscode",
            "prompt": "private prompt",
            "last_assistant_message": "private answer",
        ], options: [.sortedKeys])

        let summary = app.hookDebugSummary(inputData: payload)

        XCTAssertTrue(summary.contains("payload=json"))
        XCTAssertTrue(summary.contains("hook_event_name='Stop'"))
        XCTAssertTrue(summary.contains("thread_id='thread-1'"))
        XCTAssertTrue(summary.contains("turn_id='turn-1'"))
        XCTAssertTrue(summary.contains("source='vscode'"))
        XCTAssertFalse(summary.contains("private prompt"))
        XCTAssertFalse(summary.contains("private answer"))
        XCTAssertFalse(summary.contains("prompt"))
        XCTAssertFalse(summary.contains("last_assistant_message"))
    }

    func testDisabledHookWritesDebugLogWithoutSchedulingFocus() throws {
        let fixture = try makeFixture()
        try writeState(CodexAutofocus.State(enabled: false), app: fixture.app)
        let payload = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop",
            "thread_id": "thread-1",
        ], options: [.sortedKeys])

        XCTAssertEqual(fixture.app.handleHook(inputData: payload), 0)

        let log = try String(contentsOf: fixture.app.debugLogURL, encoding: .utf8)
        XCTAssertTrue(log.contains("hook received enabled=false"))
        XCTAssertTrue(log.contains("hook_event_name='Stop'"))
        XCTAssertTrue(log.contains("thread_id='thread-1'"))
        XCTAssertTrue(log.contains("autofocus skipped reason=disabled"))
        XCTAssertFalse(log.contains("focus starting"))
        XCTAssertFalse(log.contains("focus open_exit"))
    }

    func testNullTranscriptHookWritesDebugLogWithoutFocusing() throws {
        let fixture = try makeFixture()
        let payload = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Stop",
            "session_id": "internal-session",
            "turn_id": "internal-turn",
            "transcript_path": NSNull(),
        ], options: [.sortedKeys])

        XCTAssertEqual(fixture.app.handleHook(inputData: payload), 0)

        let log = try String(contentsOf: fixture.app.debugLogURL, encoding: .utf8)
        XCTAssertTrue(log.contains("hook received enabled=true"))
        XCTAssertTrue(log.contains("session_id='internal-session'"))
        XCTAssertTrue(log.contains("turn_id='internal-turn'"))
        XCTAssertTrue(log.contains("transcript_path='<null>'"))
        XCTAssertTrue(log.contains("autofocus skipped reason=ephemeral_session"))
        XCTAssertFalse(log.contains("focus starting"))
        XCTAssertFalse(log.contains("focus open_exit"))
    }

    func testDefaultMenuBarAppPathUsesStableHomebrewOptPath() throws {
        let fixture = try makeFixture()

        XCTAssertEqual(
            fixture.app.defaultMenuBarAppPath(binaryPath: "/opt/homebrew/bin/codex-autofocus"),
            "/opt/homebrew/opt/codex-autofocus/Codex Autofocus.app"
        )
        XCTAssertEqual(
            fixture.app.defaultMenuBarAppPath(binaryPath: "/usr/local/bin/codex-autofocus"),
            "/usr/local/opt/codex-autofocus/Codex Autofocus.app"
        )
    }

    func testInstallAppShortcutCreatesUserApplicationsSymlink() throws {
        let fixture = try makeFixture()
        let appBundle = try makeFakeApp(in: fixture.root)

        XCTAssertTrue(try fixture.app.installAppShortcut(appPath: appBundle.path))
        XCTAssertTrue(fixture.app.appShortcutStatus(appPath: appBundle.path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: fixture.app.appShortcutURL.path),
            appBundle.path
        )
        XCTAssertFalse(try fixture.app.installAppShortcut(appPath: appBundle.path))
    }

    func testInstallAppShortcutRefusesExistingNonSymlink() throws {
        let fixture = try makeFixture()
        let appBundle = try makeFakeApp(in: fixture.root)
        try FileManager.default.createDirectory(at: fixture.app.userApplicationsURL, withIntermediateDirectories: true)
        try "not managed".write(to: fixture.app.appShortcutURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try fixture.app.installAppShortcut(appPath: appBundle.path)) { error in
            XCTAssertTrue(String(describing: error).contains("A file already exists"))
        }
    }

    func testLaunchAtLoginWritesLaunchAgent() throws {
        let fixture = try makeFixture()
        let appBundle = try makeFakeApp(in: fixture.root)

        XCTAssertFalse(fixture.app.loginItemStatus(appPath: appBundle.path))
        XCTAssertTrue(try fixture.app.setLaunchAtLogin(true, appPath: appBundle.path))
        XCTAssertTrue(fixture.app.loginItemStatus(appPath: appBundle.path))
        XCTAssertFalse(try fixture.app.setLaunchAtLogin(true, appPath: appBundle.path))

        let plist = try String(contentsOf: fixture.app.loginAgentURL, encoding: .utf8)
        XCTAssertTrue(plist.contains(CodexAutofocus.loginAgentLabel))
        XCTAssertTrue(plist.contains(appBundle.path))
        XCTAssertTrue(plist.contains("RunAtLoad"))

        XCTAssertTrue(try fixture.app.setLaunchAtLogin(false, appPath: appBundle.path))
        XCTAssertFalse(fixture.app.loginItemStatus(appPath: appBundle.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.app.loginAgentURL.path))
    }

    private struct Fixture {
        var root: URL
        var app: CodexAutofocus
        var binaryPath: String
    }

    private func makeFixture(binaryPath explicitBinaryPath: String? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-autofocus-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let app = CodexAutofocus(homeDirectory: root)
        let binaryPath = explicitBinaryPath ?? codexHome.appendingPathComponent("bin/codex-autofocus").path
        return Fixture(root: root, app: app, binaryPath: binaryPath)
    }

    private func writeState(_ state: CodexAutofocus.State, app: CodexAutofocus) throws {
        try FileManager.default.createDirectory(at: app.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        try encoder.encode(state).write(to: app.stateURL, options: .atomic)
    }

    private func makeFakeApp(in root: URL) throws -> URL {
        let appBundle = root.appendingPathComponent("Codex Autofocus.app", isDirectory: true)
        let contents = appBundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key>
          <string>Codex Autofocus</string>
        </dict>
        </plist>
        """.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        return appBundle
    }
}
