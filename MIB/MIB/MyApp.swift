import SwiftUI
import SwiftData

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Relatorio.self,
            Lancamento.self
        ])
    }
}
//commit teste pra atualizar nome da branch
