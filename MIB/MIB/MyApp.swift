import SwiftUI
import SwiftData

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ResultadoFaturaView()   
        }
        .modelContainer(for: [
            Relatorio.self,
            Lancamento.self
        ])
    }
}
