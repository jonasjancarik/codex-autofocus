import Foundation

public struct NotifyCommand: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var tomlArray: String {
        ([executable] + arguments)
            .map(Self.tomlString)
            .joined(separator: ", ")
            .withBrackets
    }

    public static func fromTomlArray(_ value: String) throws -> NotifyCommand {
        var parser = TomlStringArrayParser(value)
        let values = try parser.parse()
        guard let executable = values.first else {
            throw CodexAutofocusError.invalidNotifyValue("notify array must contain at least an executable")
        }
        return NotifyCommand(executable: executable, arguments: Array(values.dropFirst()))
    }

    private static func tomlString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }
}

private extension String {
    var withBrackets: String { "[\(self)]" }
}

private struct TomlStringArrayParser {
    private let characters: [Character]
    private var index: Int = 0

    init(_ value: String) {
        characters = Array(value)
    }

    mutating func parse() throws -> [String] {
        try consumeWhitespace()
        try consume("[")
        var values: [String] = []

        while true {
            try consumeWhitespace()
            if peek() == "]" {
                index += 1
                try consumeWhitespace()
                guard isAtEnd else {
                    throw CodexAutofocusError.invalidNotifyValue("unexpected content after notify array")
                }
                return values
            }

            values.append(try parseString())
            try consumeWhitespace()

            switch peek() {
            case ",":
                index += 1
            case "]":
                continue
            default:
                throw CodexAutofocusError.invalidNotifyValue("expected comma or closing bracket in notify array")
            }
        }
    }

    private mutating func parseString() throws -> String {
        try consume("\"")
        var output = ""

        while !isAtEnd {
            let character = characters[index]
            index += 1

            if character == "\"" {
                return output
            }

            if character == "\\" {
                guard !isAtEnd else {
                    throw CodexAutofocusError.invalidNotifyValue("unterminated escape sequence in notify string")
                }
                let escaped = characters[index]
                index += 1
                switch escaped {
                case "\\": output.append("\\")
                case "\"": output.append("\"")
                case "n": output.append("\n")
                case "r": output.append("\r")
                case "t": output.append("\t")
                default:
                    throw CodexAutofocusError.invalidNotifyValue("unsupported escape sequence \\\(escaped)")
                }
            } else {
                output.append(character)
            }
        }

        throw CodexAutofocusError.invalidNotifyValue("unterminated notify string")
    }

    private mutating func consume(_ expected: Character) throws {
        guard peek() == expected else {
            throw CodexAutofocusError.invalidNotifyValue("expected '\(expected)'")
        }
        index += 1
    }

    private mutating func consumeWhitespace() throws {
        while let character = peek(), character.isWhitespace {
            index += 1
        }
    }

    private func peek() -> Character? {
        isAtEnd ? nil : characters[index]
    }

    private var isAtEnd: Bool {
        index >= characters.count
    }
}
