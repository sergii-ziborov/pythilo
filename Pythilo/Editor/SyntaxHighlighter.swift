import Foundation

enum SyntaxTokenKind: String, CaseIterable, Sendable {
    case comment
    case string
    case keyword
    case type
    case number
    case macro
    case attribute
    case section
    case key
}

struct SyntaxToken: Equatable, Sendable {
    let kind: SyntaxTokenKind
    let range: NSRange
}

enum SyntaxHighlighter {
    static func tokens(in source: String, filePath: String) -> [SyntaxToken] {
        switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "py", "pyi": pythonTokens(in: source)
        case "toml", "cfg", "ini": tomlTokens(in: source)
        case "json", "ipynb": jsonTokens(in: source)
        case "md", "markdown": markdownTokens(in: source)
        case "html", "htm": htmlTokens(in: source)
        default: []
        }
    }

    private static let pythonKeywords = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break", "case", "class",
        "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if",
        "import", "in", "is", "lambda", "match", "nonlocal", "not", "or", "pass", "raise", "return",
        "self", "try", "type", "while", "with", "yield",
    ].joined(separator: "|")

    private static let pythonPattern = #"""
    (?<comment>#[^\n]*)|(?<string>(?i:[rbuf]{0,2})(?:"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z)|"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?))|(?<attribute>^[ \t]*@[A-Za-z_][\w.]*)|(?<keyword>\b(?:\#(pythonKeywords))\b)|(?<number>\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?j?)\b)|(?<type>\b[A-Za-z_]\w*(?=\s*\())
    """#

    private static let pythonExpression: NSRegularExpression? = {
        let pattern = pythonPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }()

    private static func pythonTokens(in source: String) -> [SyntaxToken] {
        collect(pythonExpression, source: source, groups: [
            ("comment", .comment), ("string", .string), ("attribute", .attribute),
            ("keyword", .keyword), ("number", .number), ("type", .type),
        ])
    }

    private static func tomlTokens(in source: String) -> [SyntaxToken] {
        let pattern = #"(?<comment>#[^\n]*)|(?<section>^\s*\[[^\]\n]*\]+)|(?<string>"(?:\\.|[^"\\\n])*"|'[^'\n]*')|(?<key>^\s*[A-Za-z0-9_.-]+(?=\s*=))|(?<number>\b\d[\d_.]*\b)|(?<keyword>\b(?:true|false)\b)"#
        return matches(pattern, source: source, groups: [
            ("comment", .comment), ("section", .section), ("string", .string),
            ("key", .key), ("number", .number), ("keyword", .keyword),
        ])
    }

    private static func jsonTokens(in source: String) -> [SyntaxToken] {
        let pattern = #"(?<key>"(?:\\.|[^"\\\n])*"(?=\s*:))|(?<string>"(?:\\.|[^"\\\n])*")|(?<number>-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(?<keyword>\b(?:true|false|null)\b)"#
        return matches(pattern, source: source, groups: [
            ("key", .key), ("string", .string), ("number", .number), ("keyword", .keyword),
        ])
    }

    private static func markdownTokens(in source: String) -> [SyntaxToken] {
        let pattern = #"(?<section>^#{1,6} [^\n]*)|(?<string>`[^`\n]*`)|(?<keyword>\*\*[^*\n]+\*\*)"#
        return matches(pattern, source: source, groups: [
            ("section", .section), ("string", .string), ("keyword", .keyword),
        ])
    }

    private static func htmlTokens(in source: String) -> [SyntaxToken] {
        let pattern = #"(?<comment><!--[\s\S]*?-->)|(?<attribute>\{[{%][\s\S]*?[%}]\})|(?<string>"[^"\n]*")|(?<keyword></?[A-Za-z][\w-]*)"#
        return matches(pattern, source: source, groups: [
            ("comment", .comment), ("attribute", .attribute), ("string", .string), ("keyword", .keyword),
        ])
    }

    private static func matches(_ pattern: String, source: String, groups: [(String, SyntaxTokenKind)]) -> [SyntaxToken] {
        collect(try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]), source: source, groups: groups)
    }

    private static func collect(_ expression: NSRegularExpression?, source: String, groups: [(String, SyntaxTokenKind)]) -> [SyntaxToken] {
        guard let expression else { return [] }
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.matches(in: source, range: fullRange).compactMap { match in
            for (group, kind) in groups {
                let range = match.range(withName: group)
                if range.location != NSNotFound { return SyntaxToken(kind: kind, range: range) }
            }
            return nil
        }
    }
}
