import SwiftUI

@main
struct BadmintonApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
        }
    }
}
