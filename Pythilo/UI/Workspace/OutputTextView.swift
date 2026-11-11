import SwiftUI
import UIKit

/// Program output. A text view, because output can be hundreds of thousands of
/// characters and only ever grows at the end.
struct OutputTextView: UIViewRepresentable {
    let chunks: [OutputChunk]
    let revision: Int
    var fontSize: CGFloat = 13.5
    var bottomInset: CGFloat = 0

    final class Coordinator {
        var revision = -1
        var ids: [Int] = []
        var lastLength = 0
        var fontSize: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.dataDetectorTypes = []
        view.accessibilityIdentifier = "output-text"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.contentInset.bottom = bottomInset
        let coordinator = context.coordinator
        guard coordinator.revision != revision || coordinator.fontSize != fontSize else { return }
        let nearBottom = view.contentOffset.y + view.bounds.height >= view.contentSize.height - 60
        let storage = view.textStorage

        let appended = coordinator.fontSize == fontSize
            && !coordinator.ids.isEmpty
            && chunks.map(\.id).starts(with: coordinator.ids)
        if appended {
            storage.beginEditing()
            for (index, chunk) in chunks.enumerated() where index >= coordinator.ids.count - 1 {
                let already = index == coordinator.ids.count - 1 ? coordinator.lastLength : 0
                let text = chunk.text as NSString
                if text.length > already {
                    storage.append(attributed(text.substring(from: already), kind: chunk.kind))
                }
            }
            storage.endEditing()
        } else {
            let full = NSMutableAttributedString()
            for chunk in chunks { full.append(attributed(chunk.text, kind: chunk.kind)) }
            storage.setAttributedString(full)
        }
        coordinator.ids = chunks.map(\.id)
        coordinator.lastLength = ((chunks.last?.text ?? "") as NSString).length
        coordinator.revision = revision
        coordinator.fontSize = fontSize
        if nearBottom, view.bounds.height > 0 {
            view.layoutIfNeeded()
            let y = max(-view.contentInset.top, view.contentSize.height - view.bounds.height + view.contentInset.bottom)
            view.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }

    private func attributed(_ text: String, kind: OutputChunk.Kind) -> NSAttributedString {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        guard kind == .stderr else {
            let color: UIColor = switch kind {
            case .input: UIColor(AppTheme.blue)
            case .system: UIColor(AppTheme.muted)
            default: UIColor(AppTheme.primary)
            }
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        // Test runners, Django and logging write progress to stderr: "OK" is not an error.
        // Red is kept for the lines that report one.
        let result = NSMutableAttributedString()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let piece = line.offset > 0 ? "\n" + line.element : String(line.element)
            let color = Self.isErrorLine(line.element) ? UIColor(AppTheme.coralInk) : UIColor(AppTheme.secondary)
            result.append(NSAttributedString(string: piece, attributes: [.font: font, .foregroundColor: color]))
        }
        return result
    }

    static func isErrorLine(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let markers = ["Traceback", "Error", "Exception", "FAILED", "FAIL:", "ERROR", "error:", "failed", "Failed", "fatal", "CRITICAL", "Warning", "WARNING", "  File \"", "^"]
        return markers.contains { trimmed.contains($0) || line.hasPrefix($0) }
    }
}
