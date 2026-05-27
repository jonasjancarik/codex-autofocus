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

    private struct Fixture {
        var root: URL
        var app: CodexAutofocus
        var binaryPath: String
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-autofocus-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let app = CodexAutofocus(homeDirectory: root)
        let binaryPath = codexHome.appendingPathComponent("bin/codex-autofocus").path
        return Fixture(root: root, app: app, binaryPath: binaryPath)
    }

    private func writeState(_ state: CodexAutofocus.State, app: CodexAutofocus) throws {
        try FileManager.default.createDirectory(at: app.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        try encoder.encode(state).write(to: app.stateURL, options: .atomic)
    }
}
