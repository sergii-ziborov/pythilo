import Combine
import GameController
import SwiftUI
import UIKit

/// Which arrangement a screen gets. Each one is its own design, because a phone
/// held sideways, a folded Duo and a tablet want different things from the same
/// panels. Resolved from the real size and the hinge, never from a device name.
enum WorkspaceLayout: Equatable {
    case phone
    case phoneLandscape
    case duoLaptop(top: CGFloat, hinge: CGFloat)
    case duoBook(left: CGFloat, hinge: CGFloat)
    case duoFlat
    case cover
    case padLandscape
    case padPortrait

    static func resolve(size: CGSize, container: CGRect, fold: FoldReading) -> WorkspaceLayout {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return size.width > size.height ? .padLandscape : .padPortrait
        }
        if let band = FoldLayout.resolved(container: container, reading: fold) {
            if band.axis == .horizontal, let top = FoldLayout.laptopTop(containerHeight: size.height, hinge: band.frame) {
                return .duoLaptop(top: top, hinge: band.frame.height)
            }
            if band.axis == .vertical, let left = FoldLayout.bookSidebarWidth(containerWidth: size.width, hinge: band.frame) {
                return .duoBook(left: left, hinge: band.frame.width)
            }
        }
        if size.width > size.height {
            return size.height < 500 ? .phoneLandscape : .duoFlat
        }
        if size.width >= 600 { return .duoFlat }
        if size.width >= 450, size.height <= 720 { return .cover }
        return .phone
    }
}

@MainActor
@Observable
final class KeyboardObserver {
    private(set) var isVisible = false
    private(set) var height: CGFloat = 0
    private(set) var hasHardwareKeyboard = GCKeyboard.coalesced != nil
    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        // Every notice is read by where the keyboard ends up. When the terminal's
        // field is disabled and enabled again in one moment (a server restarting
        // around a command), a hide notice can land after the next show; the
        // did-change notice then settles the real state, so the panel never
        // keeps the dock's gap under a keyboard that is up.
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidShowNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                MainActor.assumeIsolated { self?.update(frame) }
            })
        }
        tokens.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hasHardwareKeyboard = true }
        })
        tokens.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hasHardwareKeyboard = false }
        })
    }

    private func update(_ frame: CGRect) {
        guard frame != .zero else { return }
        let screenHeight = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }.first ?? 0
        let covered = max(0, screenHeight - frame.minY)
        height = covered
        // A hardware keyboard leaves only the short accessory bar on screen.
        isVisible = covered > 120
    }
}

/// Which side of a sideways phone the camera is on.
func cameraIsOnLeading() -> Bool {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    return scene?.effectiveGeometry.interfaceOrientation != .landscapeLeft
}
