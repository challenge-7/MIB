import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {

    @Environment(\.modelContext)
    private var contexto

    @Query(
        sort: \Relatorio.dataCriacao,
        order: .reverse
    )
    private var relatoriosSalvos: [Relatorio]

    @StateObject
    private var viewModel = ImportacaoViewModel()

    @State private var mostrarArquivos = false
    @State private var mostrarDescarte = false
    @State private var erroSalvamento: String?

    // Identificação do banco
    @State private var nomeBanco: String?
    @State private var erroBanco: String?
    @State private var identificandoBanco = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.etapa {

                case .importacao:
                    telaImportacao

                case .revisao:
                    RevisaoView(viewModel: viewModel)

                case .previa:
                    if let temporario = viewModel.relatorioTemporario {
                        RelatorioView(
                            nome: temporario.nome,
                            lancamentos: temporario.lancamentos,
                            onConcluir: {
                                concluirRelatorio()
                            },
                            onVoltar: {
                                viewModel.voltarParaRevisao()
                            }
                        )
                    }
                }
            }
            .navigationTitle("MIB")
            .fileImporter(
                isPresented: $mostrarArquivos,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { resultado in
                do {
                    let urls = try resultado.get()
                    viewModel.importarPDFs(urls)

                    // Identifica o banco da primeira fatura selecionada
                    if let primeiraURL = urls.first {
                        analisarBanco(primeiraURL)
                    }
                } catch {
                    erroSalvamento = error.localizedDescription
                }
            }
            .alert(
                "Erro",
                isPresented: Binding(
                    get: { erroSalvamento != nil },
                    set: { if !$0 { erroSalvamento = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    erroSalvamento = nil
                }
            } message: {
                Text(erroSalvamento ?? "")
            }
            .toolbar {
                if viewModel.etapa != .importacao {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Descartar", role: .destructive) {
                            mostrarDescarte = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Descartar relatório?",
                isPresented: $mostrarDescarte
            ) {
                Button("Descartar", role: .destructive) {
                    viewModel.descartar()
                }
            } message: {
                Text("As alterações não serão salvas.")
            }
        }
    }

    private var telaImportacao: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("Suas faturas, uma só visão.")
                    .font(.title2.bold())

                Text(viewModel.mensagem)
                    .foregroundStyle(.secondary)

                Button {
                    mostrarArquivos = true
                } label: {
                    Label(
                        "Importar faturas",
                        systemImage: "doc.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.processando)

                ForEach(viewModel.faturas) { fatura in
                    Label(
                        fatura.nomeArquivo,
                        systemImage: "doc.text"
                    )
                    .font(.subheadline)
                }

                // Identificação do banco
                if identificandoBanco {
                    ProgressView("Identificando instituição financeira...")
                }

                if let nomeBanco {
                    Label(nomeBanco, systemImage: "building.columns")
                        .font(.headline)
                }

                if let erroBanco {
                    Text(erroBanco)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if !viewModel.faturas.isEmpty {
                    Button {
                        Task {
                            await viewModel.analisarFaturas()
                        }
                    } label: {
                        Text("Gerar relatório")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.processando)
                }

                if viewModel.processando {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: viewModel.progresso)

                        Text("Interpretando as faturas...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("Histórico de relatórios")
                    .font(.title2.bold())

                if relatoriosSalvos.isEmpty {
                    ContentUnavailableView(
                        "Nenhum relatório salvo",
                        systemImage: "doc.text",
                        description: Text(
                            "Seus relatórios concluídos aparecerão aqui."
                        )
                    )
                } else {
                    ForEach(relatoriosSalvos) { relatorio in
                        NavigationLink {
                            RelatorioView(
                                nome: relatorio.nome,
                                lancamentos: relatorio.lancamentos.map {
                                    LancamentoTemporario(
                                        data: $0.data,
                                        descricao: $0.descricao,
                                        valorCentavos: $0.valorCentavos,
                                        tipo: $0.tipo,
                                        categoria: $0.categoria,
                                        nomeArquivoOrigem:
                                            $0.nomeArquivoOrigem
                                    )
                                }
                            )
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")

                                VStack(alignment: .leading) {
                                    Text(relatorio.nome)
                                        .font(.headline)

                                    Text(relatorio.dataCriacao, style: .date)
                                        .font(.caption)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                            }
                            .padding()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Identificação do banco

    private func analisarBanco(_ url: URL) {

        nomeBanco = nil
        erroBanco = nil
        identificandoBanco = true

        Task {

            defer { identificandoBanco = false }

            do {
                nomeBanco = try await IdentificadorBancoService()
                    .identificarBanco(no: url)
            } catch {
                erroBanco = error.localizedDescription
            }
        }
    }

    // MARK: - Concluir relatório

    private func concluirRelatorio() {
        do {
            try viewModel.concluirRelatorio(
                contexto: contexto
            )
        } catch {
            erroSalvamento = error.localizedDescription
        }
    }
}
