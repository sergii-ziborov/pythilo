import Foundation

struct EditorDiagnostic: Identifiable, Equatable, Sendable {
    struct Span: Equatable, Sendable {
        let fileName: String
        let lineStart: Int
        let lineEnd: Int
        let columnStart: Int
        let columnEnd: Int
        let isPrimary: Bool
        let label: String?
        let sourceLine: String
    }

    let id: UUID
    let level: String
    let message: String
    let spans: [Span]
}

/// Actions from the text selection menu.
enum EditorSemanticAction: String, CaseIterable, Sendable {
    case complete
    case rename

    var title: String {
        switch self {
        case .complete: "Complete"
        case .rename: "Rename"
        }
    }
}

/// Another participant's selection in a shared room.
struct PlaygroundRemoteSelection: Codable, Equatable, Sendable, Identifiable {
    let clientID: UInt64
    let name: String
    let color: String
    let file: String
    let anchor: Int
    let head: Int
    var id: UInt64 { clientID }
    var range: NSRange { NSRange(location: min(anchor, head), length: abs(anchor - head)) }
}


/// One change between two versions of a file, reduced to what a diagnostic
/// span needs to know: which lines had their text changed, and how the lines
/// below the change moved.
///
/// Compiler positions describe the text that was built. Once the reader
/// edits, a span left at its old line either underlines whatever text has
/// since moved there or keeps marking a line that is already fixed. Folding
/// each edit into the spans as it happens keeps them honest between builds.
struct SourceLineEdit: Equatable, Sendable {
    /// Lines of the old text whose content changed, 1-based and inclusive.
    /// Nil when whole lines were inserted or removed without touching the
    /// text around them.
    let touchedLines: ClosedRange<Int>?
    /// The first old line that moved, and by how many lines (negative when
    /// lines above it were removed).
    let shiftFrom: Int
    let delta: Int

    private static let newline = UInt16(10)

    /// The edit that turns `old` into `new`, or nil when they are the same.
    ///
    /// The change is taken to be the region between the longest common prefix
    /// and suffix. That is exact for a single keystroke, paste or replacement,
    /// which is how the editor sees text change; two separate edits arriving
    /// together merge into one wider region, which can only over-invalidate.
    static func between(_ old: String, _ new: String) -> SourceLineEdit? {
        let before = Array(old.utf16)
        let after = Array(new.utf16)
        let shortest = min(before.count, after.count)

        var start = 0
        while start < shortest, before[start] == after[start] { start += 1 }
        guard start < before.count || start < after.count else { return nil }

        var common = 0
        while common < shortest - start,
              before[before.count - 1 - common] == after[after.count - 1 - common] {
            common += 1
        }
        let removedLength = before.count - common - start
        let insertedLength = after.count - common - start

        // A block inserted or removed among repeated characters — an indented
        // line between indented lines, a blank line next to another — can be
        // described from several positions. Where one of them makes the block
        // whole lines, use it, so a line pasted or deleted counts as one line
        // rather than as the tail of one and the head of the next.
        if removedLength == 0 {
            start = alignedStart(of: start, length: insertedLength, in: after)
        } else if insertedLength == 0 {
            start = alignedStart(of: start, length: removedLength, in: before)
        }
        let removed = before[start..<(start + removedLength)]
        let inserted = after[start..<(start + insertedLength)]

        let lineAtStart = 1 + count(of: newline, in: before[..<start])
        let removedLines = count(of: newline, in: removed)
        let insertedLines = count(of: newline, in: inserted)
        let delta = insertedLines - removedLines
        let atLineStart = start == 0 || before[start - 1] == newline
        let atLineEnd = start == before.count || before[start] == newline
        let removedEndsAtLineEnd = removed.endIndex == before.count
            || before[removed.endIndex] == newline

        if atLineStart,
           removed.isEmpty || removed.last == newline,
           inserted.isEmpty || inserted.last == newline {
            // Whole lines swapped in front of `lineAtStart`: the removed ones
            // are gone and the line that stood there is now further down.
            return SourceLineEdit(
                touchedLines: removedLines > 0
                    ? lineAtStart...(lineAtStart + removedLines - 1)
                    : nil,
                shiftFrom: lineAtStart + removedLines,
                delta: delta
            )
        }
        if atLineEnd,
           removed.isEmpty || removedEndsAtLineEnd,
           inserted.isEmpty || inserted.first == newline {
            // Whole lines swapped after `lineAtStart`, which itself is intact.
            return SourceLineEdit(
                touchedLines: removedLines > 0
                    ? (lineAtStart + 1)...(lineAtStart + removedLines)
                    : nil,
                shiftFrom: lineAtStart + removedLines + 1,
                delta: delta
            )
        }
        // The change starts inside a line, so that line and every line the
        // removed text ran into now read differently.
        return SourceLineEdit(
            touchedLines: lineAtStart...(lineAtStart + removedLines),
            shiftFrom: lineAtStart + removedLines + 1,
            delta: delta
        )
    }

    /// Where a span sits after this edit, or nil when the edit changed the
    /// text it pointed at.
    func rebase(_ span: EditorDiagnostic.Span) -> EditorDiagnostic.Span? {
        if let touchedLines,
           span.lineStart <= touchedLines.upperBound,
           span.lineEnd >= touchedLines.lowerBound {
            return nil
        }
        guard span.lineEnd >= shiftFrom else { return span }
        let lineStart = span.lineStart >= shiftFrom ? span.lineStart + delta : span.lineStart
        let lineEnd = span.lineEnd + delta
        guard lineStart >= 1, lineEnd >= lineStart else { return nil }
        return EditorDiagnostic.Span(
            fileName: span.fileName,
            lineStart: lineStart,
            lineEnd: lineEnd,
            columnStart: span.columnStart,
            columnEnd: span.columnEnd,
            isPrimary: span.isPrimary,
            label: span.label,
            sourceLine: span.sourceLine
        )
    }

    /// Among the positions that describe the same insertion or removal of a
    /// block, the first at which the block is whole lines — or `start` when
    /// there is none.
    private static func alignedStart(of start: Int, length: Int, in text: [UInt16]) -> Int {
        guard length > 0 else { return start }
        var lowest = start
        while lowest > 0, text[lowest - 1] == text[lowest - 1 + length] { lowest -= 1 }
        var highest = start
        while highest + length < text.count, text[highest] == text[highest + length] {
            highest += 1
        }

        for candidate in lowest...highest {
            let atLineStart = candidate == 0 || text[candidate - 1] == newline
            if atLineStart, text[candidate + length - 1] == newline { return candidate }
        }
        for candidate in lowest...highest {
            let endsAtLineEnd = candidate + length == text.count
                || text[candidate + length] == newline
            if text[candidate] == newline, endsAtLineEnd { return candidate }
        }
        return start
    }

    private static func count(of unit: UInt16, in units: ArraySlice<UInt16>) -> Int {
        units.reduce(into: 0) { total, next in
            if next == unit { total += 1 }
        }
    }
}
