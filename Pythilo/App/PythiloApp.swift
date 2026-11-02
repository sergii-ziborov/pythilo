import SwiftUI

@main
struct PythiloApp: App {
    @AppStorage("pythilo.appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
                .tint(AppTheme.blue)
        }
    }
}
