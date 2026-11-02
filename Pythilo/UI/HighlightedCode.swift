import SwiftUI

/// Read-only code, coloured the same as the editor.
struct HighlightedCode: View {
    let source: String
    var path = "x.py"
    var fontSize: CGFloat = 13

    private var attributed: AttributedString {
        var result = AttributedString(source)
        result.font = .system(size: fontSize, design: .monospaced)
        result.foregroundColor = AppTheme.primary
        for token in SyntaxHighlighter.tokens(in: source, filePath: path) {
            guard let range = Range(token.range, in: source),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].foregroundColor = SyntaxTheme.color(for: token.kind)
        }
        return result
    }

    var body: some View {
        Text(attributed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
