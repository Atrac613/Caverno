import SwiftUI

@main
struct CavernoWatchApp: App {
  @StateObject private var client = WatchSessionClient()
  @StateObject private var speaker = WatchSpeaker()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(client)
        .environmentObject(speaker)
        .task { client.activate() }
    }
  }
}
