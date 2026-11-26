import SwiftUI
import SwiftData

@main
struct MyApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            FaturaSalva.self,
            Lancamento.self
        ])
    }
}
