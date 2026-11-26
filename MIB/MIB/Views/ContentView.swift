import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {

    @Environment(\.modelContext)
    private var contexto

    @Query(
        sort: \FaturaSalva.dataImportacao,
        order: .reverse
    )
    private var faturasSalvas: [FaturaSalva]

    @StateObject
    private var viewModel = ImportacaoViewModel()

    @State
    private var mostrarArquivos = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // MARK: - Importação

                    VStack(alignment: .leading, spacing: 12) {

                        Text("Controle de gastos")
                            .font(.title2.bold())

                        Text("Importe sua fatura e descubra como seus gastos estão distribuídos.")
                            .foregroundStyle(.secondary)

                        Button {
                            mostrarArquivos = true
                        } label: {
                            Label(
                                "Selecionar fatura PDF",
                                systemImage: "doc.badge.plus"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.processando)

                        if let nome = viewModel.nomeArquivo {
                            Label(nome, systemImage: "doc.text")
                                .font(.subheadline)
                        }

                        Text(viewModel.mensagem)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if viewModel.processando {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView()

                                Text("Interpretando os lançamentos...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            Task {
                                await viewModel.analisarESalvar(
                                    contexto: contexto
                                )
                            }
                        } label: {
                            Text("Gerar relatório")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            viewModel.nomeArquivo == nil ||
                            viewModel.processando
                        )
                    }

                    Divider()

                    // MARK: - Histórico

                    VStack(alignment: .leading, spacing: 12) {

                        Text("Relatórios salvos")
                            .font(.title2.bold())

                        if faturasSalvas.isEmpty {

                            ContentUnavailableView(
                                "Nenhum relatório",
                                systemImage: "doc.text",
                                description: Text(
                                    "Seus relatórios aparecerão aqui após a análise."
                                )
                            )

                        } else {

                            ForEach(faturasSalvas) { fatura in

                                NavigationLink {
                                    RelatorioView(fatura: fatura)
                                } label: {

                                    HStack(spacing: 12) {

                                        Image(systemName: "doc.text")
                                            .font(.title2)

                                        VStack(
                                            alignment: .leading,
                                            spacing: 4
                                        ) {
                                            Text(fatura.nomeArquivo)
                                                .font(.headline)

                                            Text(
                                                fatura.dataImportacao,
                                                format: .dateTime
                                                    .day()
                                                    .month()
                                                    .year()
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding()
                                    .background(
                                        Color(.secondarySystemBackground),
                                        in: RoundedRectangle(
                                            cornerRadius: 12
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("MIB")
            .fileImporter(
                isPresented: $mostrarArquivos,
                allowedContentTypes: [.pdf]
            ) { resultado in

                do {
                    let url = try resultado.get()

                    viewModel.importarPDF(de: url)

                } catch {
                    print(
                        "Erro ao selecionar arquivo: \(error)"
                    )
                }
            }
        }
    }
}
