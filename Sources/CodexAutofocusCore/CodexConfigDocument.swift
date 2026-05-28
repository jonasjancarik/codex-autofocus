import Foundation

public struct CodexConfigDocument: Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }

    public func topLevelNotify() throws -> NotifyCommand? {
        for line in topLevelLines() {
            guard let value = notifyValue(in: line) else { continue }
            return try NotifyCommand.fromTomlArray(value)
        }
        return nil
    }

    public func replacingTopLevelNotify(with command: NotifyCommand) -> String {
        var lines = text.components(separatedBy: "\n")
        let replacement = "notify = \(command.tomlArray)"

        if let existingIndex = topLevelLineRange(in: lines).first(where: { notifyValue(in: lines[$0]) != nil }) {
            lines[existingIndex] = replacement
            return lines.joined(separator: "\n")
        }

        let insertionIndex = preferredNotifyInsertionIndex(in: lines)
        lines.insert(replacement, at: insertionIndex)
        return lines.joined(separator: "\n")
    }

    public func removingTopLevelNotify() -> String {
        let lines = text.components(separatedBy: "\n")
        let filtered = lines.enumerated().filter { index, line in
            !topLevelLineRange(in: lines).contains(index) || notifyValue(in: line) == nil
        }.map(\.element)
        return filtered.joined(separator: "\n")
    }

    public func settingFeature(_ feature: String, to value: Bool) -> String {
        var lines = text.components(separatedBy: "\n")
        let valueText = value ? "true" : "false"
        let replacement = "\(feature) = \(valueText)"

        guard let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = trimmed.isEmpty ? "" : "\(trimmed)\n\n"
            return "\(prefix)[features]\n\(replacement)\n"
        }

        let blockEnd = sectionEndIndex(startingAt: featuresIndex, in: lines)
        let featureLineIndexes = (featuresIndex + 1..<blockEnd).filter { key(in: lines[$0]) == feature }

        if let firstFeatureIndex = featureLineIndexes.first {
            lines[firstFeatureIndex] = replacement
            for index in featureLineIndexes.dropFirst().reversed() {
                lines.remove(at: index)
            }
            return lines.joined(separator: "\n")
        }

        lines.insert(replacement, at: blockEnd)
        return lines.joined(separator: "\n")
    }

    public func trustedHash(forHookStateKey key: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let sectionIndex = hookStateSectionIndex(for: key, in: lines) else {
            return nil
        }

        let blockEnd = sectionEndIndex(startingAt: sectionIndex, in: lines)
        for index in sectionIndex + 1..<blockEnd {
            guard self.key(in: lines[index]) == "trusted_hash",
                  let equals = lines[index].firstIndex(of: "=") else {
                continue
            }
            let valueStart = lines[index].index(after: equals)
            return parseTomlBasicString(String(lines[index][valueStart...]).trimmingCharacters(in: .whitespaces))
        }

        return nil
    }

    public func settingTrustedHash(_ trustedHash: String, forHookStateKey key: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let sectionHeader = hookStateSectionHeader(for: key)
        let replacement = "trusted_hash = \(tomlBasicString(trustedHash))"

        if let sectionIndex = hookStateSectionIndex(for: key, in: lines) {
            let blockEnd = sectionEndIndex(startingAt: sectionIndex, in: lines)
            if let hashIndex = (sectionIndex + 1..<blockEnd).first(where: { self.key(in: lines[$0]) == "trusted_hash" }) {
                lines[hashIndex] = replacement
            } else {
                lines.insert(replacement, at: blockEnd)
            }
            return lines.joined(separator: "\n")
        }

        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append(sectionHeader)
        lines.append(replacement)
        return lines.joined(separator: "\n")
    }

    private func topLevelLines() -> [String] {
        let lines = text.components(separatedBy: "\n")
        return topLevelLineRange(in: lines).map { lines[$0] }
    }

    private func topLevelLineRange(in lines: [String]) -> Range<Int> {
        let sectionIndex = lines.firstIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[")
        }
        return 0..<(sectionIndex ?? lines.count)
    }

    private func preferredNotifyInsertionIndex(in lines: [String]) -> Int {
        let topLevelRange = topLevelLineRange(in: lines)
        if let sandboxIndex = topLevelRange.last(where: { key(in: lines[$0]) == "sandbox_mode" }) {
            return sandboxIndex + 1
        }
        return topLevelRange.upperBound
    }

    private func sectionEndIndex(startingAt sectionIndex: Int, in lines: [String]) -> Int {
        for index in lines.indices.dropFirst(sectionIndex + 1) {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                return index
            }
        }
        return lines.count
    }

    private func hookStateSectionIndex(for key: String, in lines: [String]) -> Int? {
        let header = hookStateSectionHeader(for: key)
        return lines.firstIndex { line in
            line.trimmingCharacters(in: .whitespaces) == header
        }
    }

    private func hookStateSectionHeader(for key: String) -> String {
        "[hooks.state.\(tomlBasicString(key))]"
    }

    private func notifyValue(in line: String) -> String? {
        guard key(in: line) == "notify", let equals = line.firstIndex(of: "=") else {
            return nil
        }
        let valueStart = line.index(after: equals)
        return String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
    }

    private func key(in line: String) -> String? {
        let stripped = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard let equals = stripped.firstIndex(of: "=") else { return nil }
        return stripped[..<equals].trimmingCharacters(in: .whitespaces)
    }

    private func tomlBasicString(_ value: String) -> String {
        let escaped = value.map { character -> String in
            switch character {
            case "\\": return "\\\\"
            case "\"": return "\\\""
            case "\n": return "\\n"
            case "\r": return "\\r"
            case "\t": return "\\t"
            default: return String(character)
            }
        }.joined()
        return "\"\(escaped)\""
    }

    private func parseTomlBasicString(_ value: String) -> String? {
        guard value.hasPrefix("\""), value.hasSuffix("\"") else { return nil }
        var result = ""
        var iterator = value.dropFirst().dropLast().makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let escaped = iterator.next() else { return nil }
            switch escaped {
            case "\\": result.append("\\")
            case "\"": result.append("\"")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            default: return nil
            }
        }
        return result
    }
}
