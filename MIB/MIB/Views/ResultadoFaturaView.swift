//
//  ResultadoFaturaView.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//
import SwiftUI
import UniformTypeIdentifiers

struct ResultadoFaturaView: View {

    private enum Estado {
        case inicial
        case processando(String)
        case pronto(FaturaProcessada)
        case erro(String)
    }

    @State private var estado: Estado = .inicial
    @State private var mostrandoSeletor = false
    @State private var urlSelecionada: URL?
    @State private var pedindoSenha = false
    @State private var senha = ""
    @State private var tarefa: Task<Void, Never>?

    private let processador = ProcessadorFatura()

    var body: some View {
        NavigationStack {
            conteudo
                .navigationTitle("Leitor de fatura")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Escolher PDF", systemImage: "doc.badge.plus") {
                            mostrandoSeletor = true
                        }
                    }
                }
        }
        .fileImporter(
            isPresented: $mostrandoSeletor,
            allowedContentTypes: [.pdf]
        ) { resultado in
            switch resultado {
            case .success(let url):
                urlSelecionada = url
                iniciar(url: url, senha: nil)
            case .failure(let erro):
                estado = .erro(erro.localizedDescription)
            }
        }
        .alert("PDF protegido", isPresented: $pedindoSenha) {
            SecureField("Senha", text: $senha)
            Button("Abrir") {
                if let url = urlSelecionada { iniciar(url: url, senha: senha) }
                senha = ""
            }
            Button("Cancelar", role: .cancel) { senha = "" }
        } message: {
            Text("Informe a senha para abrir a fatura.")
        }
    }

    // MARK: - Conteúdo

    @ViewBuilder
    private var conteudo: some View {
        switch estado {
        case .inicial:
            ContentUnavailableView(
                "Nenhuma fatura",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Toque em Escolher PDF para ler uma fatura.")
            )

        case .processando(let etapa):
            VStack(spacing: 16) {
                ProgressView()
                Text(etapa).foregroundStyle(.secondary)
                Button("Cancelar", role: .cancel) {
                    tarefa?.cancel()
                    estado = .inicial
                }
            }

        case .erro(let mensagem):
            ContentUnavailableView(
                "Não foi possível ler",
                systemImage: "exclamationmark.triangle",
                description: Text(mensagem)
            )

        case .pronto(let fatura):
            resultados(fatura)
        }
    }

    private func resultados(_ fatura: FaturaProcessada) -> some View {
        List {
            Section("Verificação") {
                avisoReconciliacao(fatura.reconciliacao)
            }

            Section("Total por categoria") {
                let totais = fatura.totalPorCategoria
                    .sorted { $0.value > $1.value }
                ForEach(totais, id: \.key) { categoria, total in
                    LabeledContent(categoria) { Text(moeda(total)) }
                }
            }

            Section("Lançamentos (\(fatura.lancamentos.count))") {
                ForEach(fatura.lancamentos) { lancamento in
                    linha(lancamento)
                }
            }

            if !fatura.pagamentos.isEmpty {
                Section("Pagamentos (fora das despesas)") {
                    ForEach(fatura.pagamentos) { linha($0) }
                }
            }
        }
    }

    private func linha(_ lancamento: LancamentoFatura) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lancamento.descricao).lineLimit(2)
                Spacer()
                Text(moeda(lancamento.valorAssinado))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Text(lancamento.data.formatted(.dateTime.day().month().year()))
                Text(lancamento.categoria)
                if let parcela = lancamento.parcela {
                    Text("Parcela \(parcela)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func avisoReconciliacao(_ reconciliacao: Reconciliacao) -> some View {
        switch reconciliacao {
        case .conciliada:
            Label("Soma confere com o total da fatura", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)

        case .divergente(let calculado, let declarados):
            VStack(alignment: .leading, spacing: 4) {
                Label("A soma não confere. Revise os lançamentos.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Calculado: \(moeda(calculado))")
                Text("No documento: " + declarados.map(moeda).joined(separator: ", "))
            }
            .font(.footnote)

        case .semTotalNoDocumento(let calculado):
            VStack(alignment: .leading, spacing: 4) {
                Label("Total não encontrado no PDF", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
                Text("Soma calculada: \(moeda(calculado))").font(.footnote)
            }
        }
    }

    // MARK: - Ações

    private func iniciar(url: URL, senha: String?) {
        tarefa?.cancel()
        estado = .processando("Lendo o PDF...")

        tarefa = Task { @MainActor in

            do {

                print("VIEW - Iniciando processamento")

                let fatura = try await processador.processar(
                    url: url,
                    senha: senha
                ) { etapa in

                    print("VIEW - Etapa: \(etapa)")

                    estado = .processando(texto(para: etapa))
                }

                print("VIEW - Processador retornou")

                estado = .pronto(fatura)

                print("VIEW - Estado pronto configurado")

            } catch ErroLeituraPDF.senhaNecessaria {

                estado = .inicial
                pedindoSenha = true

            } catch is CancellationError {

                print("VIEW - Processamento cancelado")

            } catch {

                print("VIEW - ERRO: \(error.localizedDescription)")

                estado = .erro(error.localizedDescription)
            }
        }
    }

    private func texto(para etapa: EtapaProcessamento) -> String {
        switch etapa {
        case .lendoPDF: return "Lendo o PDF..."
        case .organizandoLinhas: return "Organizando as linhas..."
        case .categorizando: return "Categorizando com Apple Intelligence..."
        case .verificando: return "Verificando os totais..."
        }
    }

    private func moeda(_ valor: Decimal) -> String {
        valor.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
    }
}

#Preview {
    ResultadoFaturaView()
}
