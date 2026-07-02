import SwiftUI
import SwiftData
import Foundation

@main
struct PhonemeInferenceSandboxApp: App {
    @StateObject private var accent = CatalystAccent()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.catalystAccent, accent)
        }
    }
}
