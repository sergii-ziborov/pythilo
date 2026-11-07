import UIKit

/// A keyboard-owned strip. Its scrolling content is laid out independently of
/// the keyboard window's safe area and of the responder's SwiftUI layout.
@MainActor
class KeyboardShortcutAccessoryView: UIView {
    private let leadingButtons: [UIButton]
    private let shortcutButtons: [UIButton]
    private let hideButton: UIButton
    private let scrollView = UIScrollView()
    private let leadingSeparator = UIView()
    private let trailingSeparator = UIView()
    private static let barHeight: CGFloat = 52

    init(leading: [UIButton], shortcuts: [UIButton], hide: UIButton, identifier: String) {
        leadingButtons = leading
        shortcutButtons = shortcuts
        hideButton = hide
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.barHeight))
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .secondarySystemBackground
        accessibilityIdentifier = identifier
        scrollView.accessibilityIdentifier = identifier + "-symbols"
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.isDirectionalLockEnabled = true
        addSubview(scrollView)
        for button in shortcutButtons { scrollView.addSubview(button) }
        for button in leadingButtons { addSubview(button) }
        addSubview(hideButton)
        for separator in [leadingSeparator, trailingSeparator] {
            separator.backgroundColor = .separator
            addSubview(separator)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Keyboard shortcuts are created in code") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let keyHeight: CGFloat = 44
        let y = (bounds.height - keyHeight) / 2
        var x: CGFloat = 6
        for button in leadingButtons {
            let width = keyWidth(button)
            button.frame = CGRect(x: x, y: y, width: width, height: keyHeight)
            x += width + 5
        }
        leadingSeparator.frame = CGRect(x: x, y: 7, width: 1, height: max(0, bounds.height - 14))
        let hideX = max(x + 12, bounds.width - 50)
        hideButton.frame = CGRect(x: hideX, y: y, width: 44, height: keyHeight)
        trailingSeparator.frame = CGRect(x: hideX - 6, y: 7, width: 1, height: max(0, bounds.height - 14))
        let viewport = CGRect(x: x + 6, y: 0, width: max(0, hideX - x - 17), height: bounds.height)
        if scrollView.frame != viewport { scrollView.frame = viewport }
        var contentX: CGFloat = 0
        for button in shortcutButtons {
            let width = keyWidth(button)
            button.frame = CGRect(x: contentX, y: y, width: width, height: keyHeight)
            contentX += width + 5
        }
        let contentSize = CGSize(width: max(0, contentX - 5), height: bounds.height)
        if scrollView.contentSize != contentSize { scrollView.contentSize = contentSize }
        // Keep a scrolled strip in range after rotation or a keyboard switch.
        let offset = CGPoint(
            x: min(max(0, scrollView.contentOffset.x), max(0, scrollView.contentSize.width - scrollView.bounds.width)),
            y: 0
        )
        if scrollView.contentOffset != offset { scrollView.contentOffset = offset }
    }

    private func keyWidth(_ button: UIButton) -> CGFloat {
        guard let title = button.configuration?.title, !title.isEmpty else { return 44 }
        return max(44, min(120, ceil(button.sizeThatFits(CGSize(width: 120, height: 44)).width)))
    }

    static func key(title: String? = nil, image: String? = nil, label: String? = nil,
                    identifier: String? = nil, tint: UIColor = .label, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = image.flatMap { UIImage(systemName: $0) }
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        configuration.baseForegroundColor = tint
        configuration.cornerStyle = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var result = incoming
            result.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
            return result
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label ?? title
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
