import SwiftUI
import SwiftData

@main
struct PhonemeInferenceSandboxApp: App {
    @StateObject private var accent = CatalystAccent()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.catalystAccent, accent)
        }
        .modelContainer(for: VoiceProfile.self)
    }
}

@Model
class VoiceProfile {
    @Attribute(.unique) var id: String
    var name: String
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
