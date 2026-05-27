import Foundation

public struct CodexHooksDocument {
    private var root: [String: Any]

    public init() {
        root = ["hooks": [String: Any]()] 
    }

    public init(data: Data) throws {
        let value = try JSONSerialization.jsonObject(with: data)
        root = value as? [String: Any] ?? ["hooks": [String: Any]()] 
    }

    public func data() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    public func hasManagedStopHook(marker: String) -> Bool {
        !managedStopHookLocations(marker: marker).isEmpty
    }

    public func managedStopHookLocations(marker: String) -> [(groupIndex: Int, hookIndex: Int)] {
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let groups = hooks["Stop"] as? [[String: Any]] ?? []
        var locations: [(groupIndex: Int, hookIndex: Int)] = []

        for (groupIndex, group) in groups.enumerated() {
            let handlers = group["hooks"] as? [[String: Any]] ?? []
            for (hookIndex, handler) in handlers.enumerated() {
                if (handler["command"] as? String)?.contains(marker) == true {
                    locations.append((groupIndex: groupIndex, hookIndex: hookIndex))
                }
            }
        }

        return locations
    }

    @discardableResult
    public mutating func removeManagedHooks(marker: String) -> Bool {
        var changed = false
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var nextHooks: [String: Any] = [:]

        for (eventName, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                nextHooks[eventName] = value
                continue
            }

            var nextGroups: [[String: Any]] = []
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    nextGroups.append(group)
                    continue
                }

                let nextHandlers = handlers.filter { handler in
                    !((handler["command"] as? String)?.contains(marker) == true)
                }

                if nextHandlers.count != handlers.count {
                    changed = true
                }

                guard !nextHandlers.isEmpty else { continue }

                var nextGroup = group
                nextGroup["hooks"] = nextHandlers
                nextGroups.append(nextGroup)
            }

            if !nextGroups.isEmpty {
                nextHooks[eventName] = nextGroups
            } else if !groups.isEmpty {
                changed = true
            }
        }

        hooks = nextHooks
        root["hooks"] = hooks
        return changed
    }

    @discardableResult
    public mutating func upsertManagedStopHook(
        command: String,
        marker: String,
        timeout: Int,
        statusMessage: String
    ) -> Bool {
        _ = removeManagedHooks(marker: marker)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var stopGroups = hooks["Stop"] as? [[String: Any]] ?? []

        let handler: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": timeout,
            "statusMessage": statusMessage,
        ]
        stopGroups.append(["hooks": [handler]])
        hooks["Stop"] = stopGroups
        root["hooks"] = hooks
        return true
    }
}
