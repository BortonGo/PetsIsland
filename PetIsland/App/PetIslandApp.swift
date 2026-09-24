import SwiftUI

@main
struct PetIslandApp: App {
    var body: some Scene {
        WindowGroup { ContentView().tint(PetDesign.accent) }
    }
}

#Preview {
    ContentView()
}
