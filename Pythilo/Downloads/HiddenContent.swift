import Observation
import SwiftUI

/// Courses and Lab topics the person chose not to see. Hiding changes only the lists;
/// downloads, progress and drafts stay until the person removes the download as well.
@MainActor
@Observable
final class HiddenContent {
    static let shared = HiddenContent()

    private(set) var courses: Set<String>
    private(set) var labTopics: Set<String>
    private let defaults: UserDefaults
    private static let coursesKey = "pythilo.hiddenCourses"
    private static let topicsKey = "pythilo.hiddenLabTopics"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        courses = Set(defaults.stringArray(forKey: Self.coursesKey) ?? [])
        labTopics = Set(defaults.stringArray(forKey: Self.topicsKey) ?? [])
    }

    func toggleCourse(_ id: String) {
        if courses.contains(id) { courses.remove(id) } else { courses.insert(id) }
        defaults.set(courses.sorted(), forKey: Self.coursesKey)
    }

    func toggleTopic(_ id: String) {
        if labTopics.contains(id) { labTopics.remove(id) } else { labTopics.insert(id) }
        defaults.set(labTopics.sorted(), forKey: Self.topicsKey)
    }

    func showEverything() {
        courses = []; labTopics = []
        defaults.removeObject(forKey: Self.coursesKey)
        defaults.removeObject(forKey: Self.topicsKey)
    }
}

/// Download, remove and hide for one course or Lab topic, as menu items. It depends only on
/// whether the item is downloaded, never on download progress: rebuilding context menus on
/// every progress tick dismisses whatever menu is open, even in a cover above this screen.
struct ContentActionItems: View {
    let packID: String
    let noun: String
    let isReady: Bool
    let isHidden: Bool
    let toggleHidden: () -> Void
    let requestRemoval: () -> Void

    var body: some View {
        if isReady {
            Button("Remove download", systemImage: "trash", role: .destructive, action: requestRemoval)
        } else {
            Button("Download \(noun)", systemImage: "arrow.down.circle") { ContentStore.shared.download([packID]) }
        }
        Button(isHidden ? "Show \(noun)" : "Hide \(noun)", systemImage: isHidden ? "eye" : "eye.slash", action: toggleHidden)
    }
}

/// A download that the person asked to remove, waiting for confirmation.
struct RemovalTarget: Identifiable, Equatable {
    let packID: String
    let title: String
    var id: String { packID }
}

/// One confirmation per screen; rows only set the target. It lives in its own small view
/// with stored state, so a screen that redraws on every download tick does not touch a
/// presentation and dismiss menus shown above it.
private struct RemovalHost: View {
    @Binding var target: RemovalTarget?
    @State private var presented = false
    @State private var pending: RemovalTarget?
    @State private var failure: String?
    @State private var failed = false

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: target) { _, new in
                guard let new else { return }
                pending = new
                presented = true
                target = nil
            }
            .alert(pending.map { "Remove \($0.title)?" } ?? "Remove download?", isPresented: $presented) {
                Button("Remove download", role: .destructive) {
                    guard let pending else { return }
                    do { try ContentStore.shared.remove(pending.packID) } catch {
                        failure = error.localizedDescription
                        failed = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It is deleted from this device and can be downloaded again. Your progress and lesson drafts stay.")
            }
            .alert("Could not remove it", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: { Text(failure ?? "") }
    }
}

struct RemovalConfirmation: ViewModifier {
    @Binding var target: RemovalTarget?
    func body(content: Content) -> some View {
        content.background { RemovalHost(target: $target) }
    }
}

extension View {
    /// Download, remove and hide as a context menu. Removal goes through the screen's confirmation.
    func contentActions(packID: String, title: String, noun: String, isReady: Bool, isHidden: Bool,
                        remove: Binding<RemovalTarget?>, toggleHidden: @escaping () -> Void) -> some View {
        contextMenu {
            ContentActionItems(packID: packID, noun: noun, isReady: isReady, isHidden: isHidden, toggleHidden: toggleHidden) {
                remove.wrappedValue = RemovalTarget(packID: packID, title: title)
            }
        }
    }

    func removalConfirmation(_ target: Binding<RemovalTarget?>) -> some View {
        modifier(RemovalConfirmation(target: target))
    }
}

/// "3 hidden courses · Show" at the end of a list.
struct HiddenFooter: View {
    let count: Int
    let noun: String
    @Binding var showing: Bool
    let identifier: String

    var body: some View {
        if count > 0 {
            Button {
                withAnimation(.snappy(duration: 0.2)) { showing.toggle() }
            } label: {
                Label(showing ? "Hide \(count) hidden \(noun)" : "Show \(count) hidden \(noun)",
                      systemImage: showing ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.app)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// The small "Hidden" tag on a row that is shown only because hidden items are revealed.
struct HiddenTag: View {
    var body: some View {
        Label("Hidden", systemImage: "eye.slash")
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(AppTheme.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(AppTheme.raised, in: Capsule())
    }
}
