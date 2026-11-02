import CoreGraphics
import SwiftUI

enum FoldAxis: Equatable {
    /// Hinge runs across the device. The upper display holds the editor.
    case horizontal
    /// Hinge runs down the device. Files stay on one side of it.
    case vertical
}

struct FoldBand: Equatable {
    var frame: CGRect
    var axis: FoldAxis
}

struct FoldReading: Equatable {
    var globalRegions: [CGRect]
    var partiallyOpen: Bool
    var windowMidY: CGFloat

    static let none = FoldReading(globalRegions: [], partiallyOpen: false, windowMidY: 0)
}

enum FoldLayout {
    static func classify(_ frame: CGRect) -> FoldAxis? {
        guard frame.width > 8, frame.height > 8 else { return nil }
        if frame.height > frame.width * 2 { return .vertical }
        if frame.width > frame.height * 2 { return .horizontal }
        return nil
    }

    /// `regions` are in the same coordinate space as `container`.
    static func band(container: CGRect, regions: [CGRect]) -> FoldBand? {
        guard let region = regions.first(where: { $0.intersects(container) && classify($0) != nil }),
              let axis = classify(region) else { return nil }
        let local = region.offsetBy(dx: -container.minX, dy: -container.minY)
        return FoldBand(frame: local, axis: axis)
    }

    /// Device Hub can report a half-open hinge and omit the division rect.
    /// A portrait container then keeps the laptop split at the window midpoint.
    static func synthesizedLaptop(container: CGRect, partiallyOpen: Bool, windowMidY: CGFloat) -> FoldBand? {
        guard partiallyOpen, container.height > container.width, windowMidY > 0 else { return nil }
        let localY = windowMidY - container.minY
        guard localY > 80, localY < container.height - 80 else { return nil }
        return FoldBand(
            frame: CGRect(x: 0, y: localY - 6, width: container.width, height: 12),
            axis: .horizontal
        )
    }

    static func resolved(container: CGRect, reading: FoldReading) -> FoldBand? {
        if let band = band(container: container, regions: reading.globalRegions) { return band }
        return synthesizedLaptop(
            container: container,
            partiallyOpen: reading.partiallyOpen,
            windowMidY: reading.windowMidY
        )
    }

    /// Height of the editor pane above a laptop hinge. Nil when the hinge is too close to an edge to split.
    static func laptopTop(containerHeight: CGFloat, hinge: CGRect) -> CGFloat? {
        let top = hinge.minY
        let bottom = containerHeight - hinge.maxY
        guard top > 120, bottom > 100 else { return nil }
        return top
    }

    /// Width of the file column before a book hinge.
    static func bookSidebarWidth(containerWidth: CGFloat, hinge: CGRect) -> CGFloat? {
        guard hinge.minX > 140, containerWidth - hinge.maxX > 220 else { return nil }
        return hinge.minX
    }
}

private struct FoldReadingKey: EnvironmentKey {
    static let defaultValue = FoldReading.none
}

extension EnvironmentValues {
    var foldReading: FoldReading {
        get { self[FoldReadingKey.self] }
        set { self[FoldReadingKey.self] = newValue }
    }
}

/// Reads the system division band. On SDKs without the hinge API this view reports nothing.
struct HingeReader: UIViewRepresentable {
    var onChange: (FoldReading) -> Void

    func makeUIView(context: Context) -> HingeProbeView {
        let view = HingeProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: HingeProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.publish()
    }
}

final class HingeProbeView: UIView {
    var onChange: ((FoldReading) -> Void)?
    private var partiallyOpen = false
    private var lastReading = FoldReading.none

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        installHinge()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        publish()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publish()
    }

    func publish() {
        let reading = currentReading()
        guard reading != lastReading else { return }
        lastReading = reading
        DispatchQueue.main.async { [onChange] in
            onChange?(reading)
        }
    }

    private func currentReading() -> FoldReading {
        #if PYTHILO_DUO_SDK
        if #available(iOS 27.1, *) {
            let regions = reservedRegions(kind: .division)
                .filter(\.isActive)
                .map { convert($0.frame, to: nil) }
            let midY = window?.bounds.midY ?? 0
            return FoldReading(globalRegions: regions, partiallyOpen: partiallyOpen, windowMidY: midY)
        }
        #endif
        return .none
    }

    private func installHinge() {
        #if PYTHILO_DUO_SDK
        if #available(iOS 27.1, *) {
            installHinge27()
        }
        #endif
    }

    #if PYTHILO_DUO_SDK
    @available(iOS 27.1, *)
    private func installHinge27() {
        let interaction = UIHingeInteraction { [weak self] _, update in
            self?.partiallyOpen = update.hinge?.status == .partiallyOpen
            self?.publish()
        }
        addInteraction(interaction)
    }
    #endif
}
