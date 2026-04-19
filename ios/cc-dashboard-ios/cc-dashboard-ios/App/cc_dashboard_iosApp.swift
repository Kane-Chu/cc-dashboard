import SwiftUI

@main
struct cc_dashboard_iosApp: App {
    var body: some Scene {
        WindowGroup {
            SessionListView()
                .preferredColorScheme(.dark)
        }
    }
}
