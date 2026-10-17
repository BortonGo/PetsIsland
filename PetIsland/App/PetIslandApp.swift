import SwiftUI

@main
struct PetIslandApp: App {
    var body: some Scene {
        WindowGroup {
#if DEBUG
            // Hosted unit tests create their own controllers. Starting the real
            // app as well would race them for the shared widget saves.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || NSClassFromString("XCTestCase") != nil {
                Color.clear
            } else {
                ContentView().tint(PetDesign.accent)
                    .task { AuthorSupportStore.shared.startObserving() }
            }
#else
            ContentView().tint(PetDesign.accent)
                .task { AuthorSupportStore.shared.startObserving() }
#endif
        }
    }
}

#Preview {
    ContentView()
}
