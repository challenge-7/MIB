### Arquivo: \⁠ ./ViewModels/ImportacaoViewModel.swift\ ⁠
⁠ swift
//
//  ImportacaoViewModel.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import SwiftData
import Combine

enum EtapaRelatorio {
    case importacao
    case revisao
    case previa
}

@MainActor
final class ImportacaoViewModel: ObservableObject {

    @Published private(set) var faturas: [FaturaImportada] = []
    @Published var relatorioTemporario: RelatorioTemporario?

    @Published private(set) var etapa: EtapaRelatorio = .importacao
    @Published private(set) var processando = false
    @Published private(set) var mensagem = "Selecione suas faturas."
    @Published private(set) var progresso = 0.0

    private let leitorPDF = LeitorPDFService()
    private let interpretador = InterpretadorFaturaService()


    func importarPDFs(_ urls: [URL]) {

        guard !processando else { return }

        var novasFaturas: [FaturaImportada] = []

        do {
            for url in urls {
                let texto = try leitorPDF.extrairTexto(de: url)

                novasFaturas.append(
                    FaturaImportada(
                        nomeArquivo: url.lastPathComponent,
                        textoExtraido: texto
                    )
                )
            }

            guard !novasFaturas.isEmpty else {
                mensagem = "Nenhum PDF foi selecionado."
                return
            }

            faturas = novasFaturas
            relatorioTemporario = nil
            progresso = 0
            etapa = .importacao

            mensagem = "\(faturas.count) fatura(s) importada(s)."

        } catch {
            mensagem = "Erro na importação: \(error.localizedDescription)"
        }
    }

    func analisarFaturas() async {

        guard !processando else { return }

        guard !faturas.isEmpty else {
            mensagem = "Selecione pelo menos uma fatura."
            return
        }

        processando = true
        progresso = 0

        defer {
            processando = false
        }

        var lancamentos: [LancamentoTemporario] = []

        do {
            for (indice, fatura) in faturas.enumerated() {

                mensagem = """
                Analisando \(indice + 1) de \(faturas.count):
                \(fatura.nomeArquivo)
                """

                let extraidos = try await interpretador.interpretar(
                    texto: fatura.textoExtraido
                )
                
                print("Fatura: \(fatura.nomeArquivo)")
                print("Quantidade extraída: \(extraidos.count)")

                for item in extraidos {
                    print("""
                    Data: \(item.data)
                    Descrição: \(item.descricao)
                    Valor: \(item.valorOriginal)
                    Tipo: \(item.tipo)
                    --------------------
                    """)
                }
                
                for item in extraidos where item.tipo != "pagamento" {

                    guard let valor = ConversorMonetario
                        .converterParaCentavos(item.valorOriginal) else {

                        throw ErroRelatorio.valorInvalido(
                            item.descricao,
                            item.valorOriginal
                        )
                    }

                    guard valor != Int.min else {
                        throw ErroRelatorio.valorInvalido(
                            item.descricao,
                            item.valorOriginal
                        )
                    }

                    let tipo = item.tipo
                    let categoria = tipo == "estorno"
                        ? "Estornos"
                        : item.categoria

                    lancamentos.append(
                        LancamentoTemporario(
                            data: item.data,
                            descricao: item.descricao,
                            valorCentavos: abs(valor),
                            tipo: tipo,
                            categoria: categoria,
                            nomeArquivoOrigem: fatura.nomeArquivo
                        )
                    )
                }

                progresso = Double(indice + 1)
                    / Double(faturas.count)
            }

            guard !lancamentos.isEmpty else {
                mensagem = "Nenhum lançamento identificado."
                return
            }

            
            let dataFormatada = Date.now.formatted(
                .dateTime.month().year()
            )

            relatorioTemporario = RelatorioTemporario(
                nome: "Relatório de \(dataFormatada)",
                lancamentos: lancamentos
            )


            mensagem = "Interpretação concluída. Revise os gastos."
            etapa = .revisao

        } catch {
            // Não aproveitamos um resultado incompleto.
            relatorioTemporario = nil
            progresso = 0
            mensagem = "Erro na análise: \(error.localizedDescription)"
        }
    }

    func atualizarCategoria(
        id: UUID,
        categoria: String
    ) {
        guard let indice = relatorioTemporario?
            .lancamentos.firstIndex(where: { $0.id == id }) else {
            return
        }

        relatorioTemporario?
            .lancamentos[indice].categoria = categoria
    }

    func atualizarTipo(
        id: UUID,
        tipo: String
    ) {
        guard let indice = relatorioTemporario?
            .lancamentos.firstIndex(where: { $0.id == id }) else {
            return
        }

        relatorioTemporario?
            .lancamentos[indice].tipo = tipo

        if tipo == "estorno" {
            relatorioTemporario?
                .lancamentos[indice].categoria = "Estornos"

        } else if relatorioTemporario?
            .lancamentos[indice].categoria == "Estornos" {

            relatorioTemporario?
                .lancamentos[indice].categoria = "Outros"
        }
    }

    func atualizarNome(_ nome: String) {
        relatorioTemporario?.nome = nome
    }

    func visualizarRelatorio() {
        guard let relatorioTemporario,
              !relatorioTemporario.nome
                .trimmingCharacters(in: .whitespaces)
                .isEmpty else {
            mensagem = "Informe um nome para o relatório."
            return
        }

        etapa = .previa
    }

    func voltarParaRevisao() {
        etapa = .revisao
    }

    func concluirRelatorio(contexto: ModelContext) throws {

        guard etapa == .previa,
              let temporario = relatorioTemporario else {
            return
        }

        let lancamentos = temporario.lancamentos.map { item in
            Lancamento(
                data: item.data,
                descricao: item.descricao,
                valorCentavos: item.valorCentavos,
                tipo: item.tipo,
                categoria: item.categoria,
                nomeArquivoOrigem: item.nomeArquivoOrigem
            )
        }

        let relatorio = Relatorio(
            nome: temporario.nome,
            lancamentos: lancamentos
        )

        contexto.insert(relatorio)

        do {
            try contexto.save()
        } catch {
            contexto.rollback()
            throw error
        }

        // Limpa os dados temporários após salvar.
        faturas = []
        relatorioTemporario = nil
        progresso = 0
        etapa = .importacao
        mensagem = "Relatório salvo com sucesso!"
    }

    func descartar() {
        guard !processando else { return }

        faturas = []
        relatorioTemporario = nil
        progresso = 0
        etapa = .importacao
        mensagem = "Selecione suas faturas."
    }
}

enum ErroRelatorio: LocalizedError {
    case valorInvalido(String, String)

    var errorDescription: String? {
        switch self {
        case .valorInvalido(let descricao, let valor):
            return "Valor inválido em \(descricao): \(valor)"
        }
    }
}
 ⁠

---

### Arquivo: \⁠ ./Utils/ConversorMonetario.swift\ ⁠
⁠ swift
//
//  ConversorMonetario.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//


import Foundation

struct ConversorMonetario {

    static func converterParaCentavos(_ texto: String) -> Int? {

        let valorLimpo = texto
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formato = #"^-?(?:\d{1,3}(?:\.\d{3})+|\d+),\d{2}$"#

        guard valorLimpo.range(
            of: formato,
            options: .regularExpression
        ) != nil else {
            return nil
        }

        let valorNormalizado = valorLimpo
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard let valor = Decimal(
            string: valorNormalizado,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            return nil
        }

        let numero = NSDecimalNumber(decimal: valor * 100)
        let inteiro = numero.int64Value

        guard numero != .notANumber,
              numero == NSDecimalNumber(value: inteiro),
              inteiro != Int64.min else {
            return nil
        }

        return Int(exactly: inteiro)
    }
}
 ⁠

---

### Arquivo: \⁠ ./Models/ResultadoFaturaIA.swift\ ⁠
⁠ swift
//
//  ResultadoFaturaIA.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import FoundationModels

@Generable
struct LancamentoExtraido {

    @Guide(description: "Data da transação no formato DD/MM/AAAA")
    var data: String

    
    @Guide(description: """
    Nome do estabelecimento ou descrição textual da transação.

    Não inclua a data nem o valor monetário neste campo.

    Exemplo correto:
    SUPERMERCADO SOL

    Exemplo incorreto:
    SUPERMERCADO SOL 185,90
    """)
    var descricao: String


    @Guide(description: """
    Copie o valor monetário exatamente como aparece
    na fatura, sem realizar cálculos ou conversões.
    Exemplos: 185,90; 32,50; -48,70.
    Não confunda números de parcelas com valores.
    """)
    var valorOriginal: String

    @Guide(.anyOf([
        "compra",
        "estorno",
        "pagamento",
        "encargo"
    ]))
    var tipo: String

    @Guide(.anyOf([
        "Alimentação",
        "Compras",
        "Transporte",
        "Moradia",
        "Saúde",
        "Lazer",
        "Assinaturas",
        "Estornos",
        "Outros"
    ]))
    var categoria: String
}

@Generable
struct ResultadoFaturaIA {

    @Guide(description: """
    Todos os lançamentos financeiros individuais
    encontrados na fatura.
    Não inclua totais ou subtotais.
    """)
    var lancamentos: [LancamentoExtraido]
}
 ⁠

---

### Arquivo: \⁠ ./Models/Lancamento.swift\ ⁠
⁠ swift
//
//  Lancamento.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import SwiftData

@Model
final class Lancamento {

    var data: String
    var descricao: String
    var valorCentavos: Int
    var tipo: String
    var categoria: String
    var nomeArquivoOrigem: String

    init(
        data: String,
        descricao: String,
        valorCentavos: Int,
        tipo: String,
        categoria: String,
        nomeArquivoOrigem: String
    ) {
        self.data = data
        self.descricao = descricao
        self.valorCentavos = valorCentavos
        self.tipo = tipo
        self.categoria = categoria
        self.nomeArquivoOrigem = nomeArquivoOrigem
    }
}
 ⁠

---

### Arquivo: \⁠ ./Models/RelatorioTemporario.swift\ ⁠
⁠ swift
//
//  RelatorioTemporario.swift
//  MIB
//
//  Created by Gabriel Groppo on 26/11/26.
//

import Foundation

struct LancamentoTemporario: Identifiable {

    let id: UUID

    var data: String
    var descricao: String
    var valorCentavos: Int
    var tipo: String
    var categoria: String
    var nomeArquivoOrigem: String

    init(
        id: UUID = UUID(),
        data: String,
        descricao: String,
        valorCentavos: Int,
        tipo: String,
        categoria: String,
        nomeArquivoOrigem: String
    ) {
        self.id = id
        self.data = data
        self.descricao = descricao
        self.valorCentavos = valorCentavos
        self.tipo = tipo
        self.categoria = categoria
        self.nomeArquivoOrigem = nomeArquivoOrigem
    }
}

struct RelatorioTemporario {

    var nome: String
    var lancamentos: [LancamentoTemporario]
}
 ⁠

---

### Arquivo: \⁠ ./Models/FaturaImportada.swift\ ⁠
⁠ swift
//
//  FaturaImportada.swift
//  MIB
//
//  Created by Gabriel Groppo on 26/11/26.
//

import Foundation

struct FaturaImportada: Identifiable {

    let id = UUID()
    let nomeArquivo: String
    let textoExtraido: String
}
 ⁠

---

### Arquivo: \⁠ ./Models/Relatorio.swift\ ⁠
⁠ swift
//
//  Relatorio.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import SwiftData

@Model
final class Relatorio {

    var nome: String
    var dataCriacao: Date

    @Relationship(deleteRule: .cascade)
    var lancamentos: [Lancamento] = []

    init(
        nome: String,
        dataCriacao: Date = .now,
        lancamentos: [Lancamento] = []
    ) {
        self.nome = nome
        self.dataCriacao = dataCriacao
        self.lancamentos = lancamentos
    }
}
 ⁠

---

### Arquivo: \⁠ ./Models/ModelosFatura.swift\ ⁠
⁠ swift
//
//  ModelosFatura.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//

import Foundation
import CoreGraphics

struct FragmentoTexto: Sendable {
    let texto: String
    let caixa: CGRect
}

struct LinhaPagina: Sendable {
    let pagina: Int
    let texto: String
}

enum TipoLancamento: String, Sendable {
    case compra, estorno, pagamento, encargo
}

struct LancamentoFatura: Identifiable, Sendable {
    let id = UUID()
    var data: Date
    var descricao: String
    /// Sempre positivo. O sinal é decidido pelo `tipo`.
    var valor: Decimal
    var parcela: String?
    var tipo: TipoLancamento
    var categoria: String = "Outros"

    var valorAssinado: Decimal { tipo == .estorno ? -valor : valor }
}

enum Reconciliacao: Sendable {
    case conciliada
    case divergente(calculado: Decimal, declarados: [Decimal])
    case semTotalNoDocumento(calculado: Decimal)
}

struct FaturaProcessada: Sendable {
    let lancamentos: [LancamentoFatura]   // compras, estornos e encargos
    let pagamentos: [LancamentoFatura]    // ficam fora das despesas
    let reconciliacao: Reconciliacao

    var totalPorCategoria: [String: Decimal] {
        lancamentos.reduce(into: [:]) { $0[$1.categoria, default: 0] += $1.valorAssinado }
    }
}

extension String {
    var normalizado: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "pt_BR")).uppercased()
    }

    /// Chave estável do estabelecimento (usada no cache de categorias).
    var chaveEstabelecimento: String {
        let letras = normalizado.unicodeScalars.map {
            CharacterSet.letters.contains($0) ? Character($0) : " "
        }
        return String(letras)
            .split(whereSeparator: \.isWhitespace)
            .filter { $0 != "PARC" && $0 != "PARCELA" }
            .joined(separator: " ")
    }
}
 ⁠

---

### Arquivo: \⁠ ./MyApp.swift\ ⁠
⁠ swift
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
 ⁠

---

### Arquivo: \⁠ ./Views/RelatorioView.swift\ ⁠
⁠ swift
//
//  RelatorioView.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import SwiftUI

struct RelatorioView: View {

    let nome: String
    let lancamentos: [LancamentoTemporario]

    var onConcluir: (() -> Void)? = nil
    var onVoltar: (() -> Void)? = nil

    private var despesas: [LancamentoTemporario] {
        lancamentos.filter {
            $0.tipo != "pagamento" &&
            $0.tipo != "cancelado"
        }
    }

    private var categoriasAgrupadas:
        [String: [LancamentoTemporario]] {

        Dictionary(grouping: despesas) {
            $0.categoria
        }
    }

    private var totalGeral: Int {
        despesas.reduce(0) { resultado, item in
            resultado + valorLiquido(item)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text(nome)
                    .font(.title2.bold())

                Text("Total de gastos")
                    .foregroundStyle(.secondary)

                Text(formatarReais(totalGeral))
                    .font(.largeTitle.bold())

                Divider()

                Text("Gastos por categoria")
                    .font(.title2.bold())

                ForEach(
                    categoriasAgrupadas.keys.sorted(),
                    id: \.self
                ) { categoria in

                    let itens = categoriasAgrupadas[categoria] ?? []

                    let totalCategoria = itens.reduce(0) {
                        $0 + valorLiquido($1)
                    }

                    VStack(alignment: .leading, spacing: 12) {

                        HStack {
                            Text(categoria)
                                .font(.headline)

                            Spacer()

                            Text(formatarReais(totalCategoria))
                                .font(.headline)
                        }

                        ForEach(itens) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.descricao)

                                    Text(item.data)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(item.nomeArquivoOrigem)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(formatarReais(item.valorCentavos))
                            }
                        }
                    }

                    Divider()
                }

                if let onVoltar {
                    Button("Voltar para revisão") {
                        onVoltar()
                    }
                    .buttonStyle(.bordered)
                }

                if let onConcluir {
                    Button {
                        onConcluir()
                    } label: {
                        Text("Concluir")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Relatório")
    }

    private func valorLiquido(
        _ item: LancamentoTemporario
    ) -> Int {

        switch item.tipo {

        case "compra", "encargo":
            return item.valorCentavos

        case "estorno":
            return -item.valorCentavos

        case "pagamento", "cancelado":
            return 0

        default:
            return 0
        }
    }

    private func formatarReais(_ centavos: Int) -> String {
        (Decimal(centavos) / 100).formatted(
            .currency(code: "BRL")
            .locale(Locale(identifier: "pt_BR"))
        )
    }
}
 ⁠

---

### Arquivo: \⁠ ./Views/RevisaoView.swift\ ⁠
⁠ swift
//
//  RevisaoView.swift
//  MIB
//
//  Created by Gabriel Groppo on 26/11/26.
//

import SwiftUI

struct RevisaoView: View {

    @ObservedObject var viewModel: ImportacaoViewModel

    private let categorias = [
        "Alimentação",
        "Transporte",
        "Moradia",
        "Saúde",
        "Lazer",
        "Compras",
        "Assinaturas",
        "Educação",
        "Estornos",
        "Outros"
    ]


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("Revisar lançamentos")
                    .font(.title2.bold())

                Text("""
                Confira as categorias e os tipos de lançamento
                identificados pela Apple Intelligence.
                """)
                .foregroundStyle(.secondary)

                if let relatorio = viewModel.relatorioTemporario {

                    TextField(
                        "Nome do relatório",
                        text: Binding(
                            get: {
                                viewModel.relatorioTemporario?.nome ?? ""
                            },
                            set: {
                                viewModel.atualizarNome($0)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    ForEach(relatorio.lancamentos) { item in

                        VStack(alignment: .leading, spacing: 12) {

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.descricao)
                                        .font(.headline)

                                    Text(item.data)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(formatarReais(item.valorCentavos))
                                    .font(.headline)
                            }

                            Text(item.nomeArquivoOrigem)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                        
                            Picker(
                                "Categoria",
                                selection: Binding(
                                    get: {
                                        viewModel.relatorioTemporario?
                                            .lancamentos.first {
                                                $0.id == item.id
                                            }?.categoria ?? item.categoria
                                    },
                                    set: {
                                        viewModel.atualizarCategoria(
                                            id: item.id,
                                            categoria: $0
                                        )
                                    }
                                )
                            ) {
                                ForEach(categorias, id: \.self) { categoria in
                                    Text(categoria)
                                        .tag(categoria)
                                }
                            }
                            .disabled(
                                viewModel.relatorioTemporario?
                                    .lancamentos.first(where: { $0.id == item.id })?
                                    .tipo == "estorno"
                            )
                        }
                        .padding()
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }

                    Button {
                        viewModel.visualizarRelatorio()
                    } label: {
                        Text("Visualizar relatório")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func formatarReais(_ centavos: Int) -> String {
        (Decimal(centavos) / 100).formatted(
            .currency(code: "BRL")
            .locale(Locale(identifier: "pt_BR"))
        )
    }
}

 ⁠

---

### Arquivo: \⁠ ./Views/ContentView.swift\ ⁠
⁠ swift
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
 ⁠

---

### Arquivo: \⁠ ./Views/ResultadoFaturaView.swift\ ⁠
⁠ swift
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

        tarefa = Task {
            do {
                let fatura = try await processador.processar(url: url, senha: senha) { etapa in
                    Task { @MainActor in
                        estado = .processando(texto(para: etapa))
                    }
                }
                estado = .pronto(fatura)
            } catch ErroLeituraPDF.senhaNecessaria {
                estado = .inicial
                pedindoSenha = true
            } catch is CancellationError {
                // cancelado pelo usuário
            } catch {
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
 ⁠

---

### Arquivo: \⁠ ./Services/LeitorPDFService.swift\ ⁠
⁠ swift
//
//  LeitorPDFService.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import PDFKit
import Vision

enum ErroLeituraPDF: LocalizedError {
    case documentoInvalido
    case textoNaoEncontrado
    case senhaNecessaria
    case semPaginas

    var errorDescription: String? {
        switch self {
        case .documentoInvalido: return "Não foi possível abrir o arquivo PDF."
        case .textoNaoEncontrado: return "O PDF não contém texto que possa ser extraído."
        case .senhaNecessaria: return "O PDF é protegido. Informe a senha correta."
        case .semPaginas: return "O PDF não possui páginas."
        }
    }
}

struct LeitorPDFService {

    // Mantido como estava.
    func extrairTexto(de url: URL) throws -> String {
        let acessoAutorizado = url.startAccessingSecurityScopedResource()
        defer { if acessoAutorizado { url.stopAccessingSecurityScopedResource() } }

        guard let documento = PDFDocument(url: url) else {
            throw ErroLeituraPDF.documentoInvalido
        }
        guard let texto = documento.string,
              !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ErroLeituraPDF.textoNaoEncontrado
        }
        return texto
    }

    /// Fragmentos de texto com posição, página a página.
    /// Páginas sem texto digital passam por OCR local (Vision).
    @concurrent
    func extrairPaginas(de url: URL, senha: String? = nil) async throws -> [[FragmentoTexto]] {
        let acessoAutorizado = url.startAccessingSecurityScopedResource()
        defer { if acessoAutorizado { url.stopAccessingSecurityScopedResource() } }

        guard let documento = PDFDocument(url: url) else {
            throw ErroLeituraPDF.documentoInvalido
        }
        if documento.isLocked {
            guard let senha, documento.unlock(withPassword: senha) else {
                throw ErroLeituraPDF.senhaNecessaria
            }
        }
        guard documento.pageCount > 0 else { throw ErroLeituraPDF.semPaginas }

        var paginas: [[FragmentoTexto]] = []
        for indice in 0..<documento.pageCount {
            try Task.checkCancellation()
            guard let pagina = documento.page(at: indice) else {
                paginas.append([])
                continue
            }
            var fragmentos = fragmentosDigitais(de: pagina)
            if fragmentos.isEmpty {
                fragmentos = try reconhecerTexto(em: pagina)
            }
            paginas.append(fragmentos)
        }
        return paginas
    }

    nonisolated private func fragmentosDigitais(de pagina: PDFPage) -> [FragmentoTexto] {
        let area = pagina.bounds(for: .mediaBox)
        guard let selecao = pagina.selection(for: area) else { return [] }

        return selecao.selectionsByLine().compactMap { linha in
            guard let texto = linha.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !texto.isEmpty else { return nil }
            return FragmentoTexto(texto: texto, caixa: linha.bounds(for: pagina))
        }
    }

    nonisolated private func reconhecerTexto(em pagina: PDFPage) throws -> [FragmentoTexto] {
        let area = pagina.bounds(for: .mediaBox)
        guard area.width > 0, area.height > 0 else { return [] }

        let largura: CGFloat = 2000
        let imagem = pagina.thumbnail(
            of: CGSize(width: largura, height: largura * area.height / area.width),
            for: .mediaBox
        )
        guard let cgImage = imagem.cgImage else { return [] }

        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.recognitionLanguages = ["pt-BR"]
        pedido.usesLanguageCorrection = false   // números e nomes de lojas

        try VNImageRequestHandler(cgImage: cgImage).perform([pedido])

        return (pedido.results ?? []).compactMap { observacao in
            guard let texto = observacao.topCandidates(1).first?.string else { return nil }
            return FragmentoTexto(texto: texto, caixa: observacao.boundingBox)
        }
    }
}
 ⁠

---

### Arquivo: \⁠ ./Services/ReconstrutorLinhasService.swift\ ⁠
⁠ swift
//
//  ReconstrutorLinhasService.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//

import Foundation
import CoreGraphics

/// Reagrupa fragmentos de texto em linhas visuais, usando a posição vertical.
enum ReconstrutorLinhas {

    static func reconstruir(_ fragmentos: [FragmentoTexto], pagina: Int) -> [LinhaPagina] {
        guard !fragmentos.isEmpty else { return [] }

        let alturas = fragmentos.map { $0.caixa.height }.sorted()
        let tolerancia = max(alturas[alturas.count / 2] * 0.5, 0.001)

        // Origem no canto inferior esquerdo (PDFKit e Vision): maior Y = mais alto.
        let ordenados = fragmentos.sorted { $0.caixa.midY > $1.caixa.midY }

        var grupos: [[FragmentoTexto]] = []
        for fragmento in ordenados {
            if let referencia = grupos.last?.first,
               abs(referencia.caixa.midY - fragmento.caixa.midY) <= tolerancia {
                grupos[grupos.count - 1].append(fragmento)
            } else {
                grupos.append([fragmento])
            }
        }

        return grupos.map { grupo in
            let texto = grupo
                .sorted { $0.caixa.minX < $1.caixa.minX }
                .map(\.texto)
                .joined(separator: " ")
            return LinhaPagina(pagina: pagina, texto: texto)
        }
    }
}
 ⁠

---

### Arquivo: \⁠ ./Services/CategorizadorService.swift\ ⁠
⁠ swift
//
//  CategorizadorService.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//

import Foundation
import FoundationModels

enum CategoriaGasto: String, CaseIterable, Sendable {
    case alimentacao = "Alimentação"
    case transporte = "Transporte"
    case moradia = "Moradia"
    case saude = "Saúde"
    case lazer = "Lazer"
    case assinaturas = "Assinaturas"
    case compras = "Compras"
    case outros = "Outros"
}

@Generable
struct ItemCategorizado {
    @Guide(description: "Número do item, exatamente como recebido")
    var indice: Int

    @Guide(.anyOf(["Alimentação", "Transporte", "Moradia", "Saúde",
                   "Lazer", "Assinaturas", "Compras", "Outros"]))
    var categoria: String
}

@Generable
struct ResultadoCategorizacao {
    var itens: [ItemCategorizado]
}

/// Cache local estabelecimento -> categoria. Correções do usuário também entram aqui.
actor CacheCategorias {
    private let chaveDefaults = "cacheCategoriasV1"
    private var mapa: [String: String]

    init() {
        mapa = UserDefaults.standard.dictionary(forKey: chaveDefaults) as? [String: String] ?? [:]
    }

    func categoria(para chave: String) -> String? { mapa[chave] }

    func salvar(_ novos: [String: String]) {
        guard !novos.isEmpty else { return }
        mapa.merge(novos) { _, novo in novo }
        UserDefaults.standard.set(mapa, forKey: chaveDefaults)
    }

    func corrigir(descricao: String, categoria: String) {
        salvar([descricao.chaveEstabelecimento: categoria])
    }
}

struct CategorizadorService {
    let cache: CacheCategorias
    private let tamanhoLote = 20

    private let instrucoes = """
    Você categoriza estabelecimentos de faturas de cartão brasileiras.
    Responda apenas com o índice do item e a categoria.

    Categorias:
    - Alimentação: supermercados, restaurantes, cafeterias, delivery de comida.
    - Transporte: Uber, táxi, ônibus, combustível, estacionamento, pedágio.
    - Moradia: aluguel e despesas residenciais.
    - Saúde: farmácias e serviços médicos.
    - Lazer: cinema, shows, parques e entretenimento pago individualmente.
    - Assinaturas: serviços por assinatura, incluindo streaming (Netflix, Spotify, Disney+).
      Se for assinatura, use esta em vez de Lazer.
    - Compras: lojas de roupas, papelaria, utensílios, eletrônicos.
    - Outros: estabelecimento desconhecido ou sem evidência suficiente.
    """

    /// Devolve um mapa chaveEstabelecimento -> categoria.
    func categorizar(descricoes: [String]) async -> [String: String] {
        var resultado: [String: String] = [:]
        var pendentes: [(chave: String, descricao: String)] = []
        var vistos = Set<String>()

        for descricao in descricoes {
            let chave = descricao.chaveEstabelecimento
            guard !chave.isEmpty, vistos.insert(chave).inserted else { continue }
            if let existente = await cache.categoria(para: chave) {
                resultado[chave] = existente
            } else {
                pendentes.append((chave, descricao))
            }
        }

        for inicio in stride(from: 0, to: pendentes.count, by: tamanhoLote) {
            let lote = Array(pendentes[inicio..<min(inicio + tamanhoLote, pendentes.count)])
            let obtidas = (try? await categorizarLote(lote.map(\.descricao))) ?? [:]

            var novosParaCache: [String: String] = [:]
            for (posicao, item) in lote.enumerated() {
                if let categoria = obtidas[posicao] {
                    resultado[item.chave] = categoria
                    novosParaCache[item.chave] = categoria
                } else {
                    resultado[item.chave] = CategoriaGasto.outros.rawValue  // não vai para o cache
                }
            }
            await cache.salvar(novosParaCache)
        }
        return resultado
    }

    private func categorizarLote(_ descricoes: [String]) async throws -> [Int: String] {
        // Sessão nova por lote, para não acumular contexto.
        let sessao = LanguageModelSession(model: .default, instructions: instrucoes)

        let lista = descricoes.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")

        let resposta = try await sessao.respond(
            to: "Categorize cada item:\n\(lista)",
            generating: ResultadoCategorizacao.self,
            options: GenerationOptions(sampling: .greedy)
        )

        let validas = Set(CategoriaGasto.allCases.map(\.rawValue))
        var mapa: [Int: String] = [:]
        for item in resposta.content.itens
        where validas.contains(item.categoria) && descricoes.indices.contains(item.indice) {
            mapa[item.indice] = item.categoria
        }
        return mapa
    }
}
 ⁠

---

### Arquivo: \⁠ ./Services/SegmentadorLancamentos.swift\ ⁠
⁠ swift
//
//  Segmentador.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//

import Foundation

struct ResultadoSegmentacao: Sendable {
    var lancamentos: [LancamentoFatura]
    var totaisDeclarados: [Decimal]
}

/// Transforma linhas em lançamentos usando padrões universais (data, valor, parcela, seção).
/// Nada aqui depende do banco emissor.
struct SegmentadorLancamentos {

    private let dataInicio = #/^(\d{2})\/(\d{2})(?:\/(\d{2,4}))?\s+/#
    private let valor = #/(-)?(?:R\$\s?)?(\d{1,3}(?:\.\d{3})*,\d{2})(\s?CR\b)?/#
    private let parcelaExplicita = #/(?i)\bPARC(?:ELA)?\.?\s*(\d{1,2})\s*\/\s*(\d{1,2})/#
    private let parcelaFinal = #/\b(\d{2})\/(\d{2})\s*$/#
    private let vencimento = #/(?i)vencimento.*?(\d{2})\/(\d{2})\/(\d{4})/#
    private let totalFatura = #/(?i)total\s+(?:da\s+|desta\s+)?fatura|total\s+a\s+pagar/#

    func segmentar(_ linhas: [LinhaPagina]) -> ResultadoSegmentacao {
        let referencia = mesEAnoReferencia(linhas)
        var lancamentos: [LancamentoFatura] = []
        var totais: [Decimal] = []
        var secao: TipoLancamento = .compra
        var anteriorFoiLancamento = false

        for linha in linhas {
            let texto = linha.texto
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !texto.isEmpty else { continue }

            if let lancamento = lancamento(de: texto, secao: secao, referencia: referencia) {
                lancamentos.append(lancamento)
                anteriorFoiLancamento = true
                continue
            }

            if texto.firstMatch(of: totalFatura) != nil,
               let ultimo = texto.matches(of: valor).last,
               let total = decimal(de: String(ultimo.output.2)) {
                totais.append(total)
                anteriorFoiLancamento = false
                continue
            }

            if let nova = secaoDe(texto) {
                secao = nova
                anteriorFoiLancamento = false
                continue
            }

            // Descrição que quebrou para a linha de baixo.
            if anteriorFoiLancamento, podeSerContinuacao(texto),
               var ultimo = lancamentos.popLast() {
                ultimo.descricao += " " + texto
                lancamentos.append(ultimo)
            }
            anteriorFoiLancamento = false
        }

        return ResultadoSegmentacao(lancamentos: lancamentos, totaisDeclarados: totais)
    }

    // MARK: - Linha de transação

    private func lancamento(
        de texto: String,
        secao: TipoLancamento,
        referencia: (mes: Int, ano: Int)
    ) -> LancamentoFatura? {

        guard let data = texto.firstMatch(of: dataInicio),
              let dia = Int(data.output.1), let mes = Int(data.output.2),
              (1...31).contains(dia), (1...12).contains(mes),
              let ultimoValor = texto.matches(of: valor).last,
              ultimoValor.range.lowerBound >= data.range.upperBound,
              let magnitude = decimal(de: String(ultimoValor.output.2))
        else { return nil }

        let ano: Int
        if let textoAno = data.output.3, let numero = Int(textoAno) {
            ano = textoAno.count == 2 ? 2000 + numero : numero
        } else {
            ano = mes > referencia.mes ? referencia.ano - 1 : referencia.ano
        }

        var componentes = DateComponents()
        componentes.day = dia; componentes.month = mes; componentes.year = ano
        guard let dataCompleta = Calendar(identifier: .gregorian).date(from: componentes)
        else { return nil }

        let descricao = texto[data.range.upperBound..<ultimoValor.range.lowerBound]
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let credito = ultimoValor.output.1 != nil || ultimoValor.output.3 != nil

        return LancamentoFatura(
            data: dataCompleta,
            descricao: descricao,
            valor: magnitude,
            parcela: parcela(em: descricao),
            tipo: tipo(descricao: descricao, secao: secao, credito: credito)
        )
    }

    private func tipo(descricao: String, secao: TipoLancamento, credito: Bool) -> TipoLancamento {
        let d = descricao.normalizado

        if d.contains("PAGAMENTO RECEBIDO") || d.contains("PAGAMENTO EFETUADO")
            || d.contains("PAGTO") { return .pagamento }
        if d.contains("ESTORNO") || d.contains("REEMBOLSO") || d.contains("DEVOLUCAO") {
            return .estorno
        }
        if ["JUROS", "MULTA", "IOF", "ANUIDADE", "TARIFA", "ENCARGO"]
            .contains(where: d.contains) { return .encargo }
        if secao == .pagamento { return .pagamento }
        if credito { return .estorno }
        return secao == .estorno || secao == .encargo ? secao : .compra
    }

    private func parcela(em descricao: String) -> String? {
        if let m = descricao.firstMatch(of: parcelaExplicita) {
            return "\(m.output.1)/\(m.output.2)"
        }
        if let m = descricao.firstMatch(of: parcelaFinal) {
            return "\(m.output.1)/\(m.output.2)"
        }
        return nil
    }

    // MARK: - Seções, continuação e referência

    private func secaoDe(_ texto: String) -> TipoLancamento? {
        guard texto.count <= 70, texto.matches(of: valor).isEmpty else { return nil }
        let t = texto.normalizado

        if t.contains("PAGAMENTO") { return .pagamento }
        if t.contains("ESTORNO") || t.contains("REEMBOLSO") || t.contains("DEVOLUC") {
            return .estorno
        }
        if ["ENCARGO", "JUROS", "MULTA", "TARIFA", "ANUIDADE", "IOF"]
            .contains(where: t.contains) { return .encargo }
        if ["COMPRAS", "TRANSAC", "LANCAMENTOS", "DESPESAS"]
            .contains(where: t.contains) { return .compra }
        return nil
    }

    private func podeSerContinuacao(_ texto: String) -> Bool {
        texto.count <= 30
            && !texto.contains(where: \.isNumber)
            && texto.matches(of: valor).isEmpty
    }

    private func mesEAnoReferencia(_ linhas: [LinhaPagina]) -> (mes: Int, ano: Int) {
        for linha in linhas {
            if let m = linha.texto.firstMatch(of: vencimento),
               let mes = Int(m.output.2), let ano = Int(m.output.3) {
                return (mes, ano)
            }
        }
        let c = Calendar(identifier: .gregorian).dateComponents([.month, .year], from: .now)
        return (c.month ?? 1, c.year ?? 2026)
    }

    private func decimal(de texto: String) -> Decimal? {
        let limpo = texto
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: limpo, locale: Locale(identifier: "en_US_POSIX"))
    }
}
 ⁠

---

### Arquivo: \⁠ ./Services/ProcessadorFaturaService.swift\ ⁠
⁠ swift
//
//  ProcessadorFaturaService.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//

import Foundation
import FoundationModels

enum EtapaProcessamento: Sendable {
    case lendoPDF
    case organizandoLinhas
    case categorizando
    case verificando
}

enum ErroFatura: LocalizedError {
    case modeloIndisponivel
    case nenhumLancamento

    var errorDescription: String? {
        switch self {
        case .modeloIndisponivel:
            return "A Apple Intelligence não está disponível neste dispositivo."
        case .nenhumLancamento:
            return "Não foi possível identificar lançamentos neste PDF."
        }
    }
}

struct ProcessadorFatura {

    private let leitor = LeitorPDFService()
    private let segmentador = SegmentadorLancamentos()
    private let categorizador: CategorizadorService

    init(cache: CacheCategorias = CacheCategorias()) {
        categorizador = CategorizadorService(cache: cache)
    }

    func processar(
        url: URL,
        senha: String? = nil,
        aoMudarEtapa: (@MainActor @Sendable (EtapaProcessamento) -> Void)? = nil
    ) async throws -> FaturaProcessada {

        guard case .available = SystemLanguageModel.default.availability else {
            throw ErroFatura.modeloIndisponivel
        }

        // 1. Leitura do PDF
        await aoMudarEtapa?(.lendoPDF)

        let paginas = try await leitor.extrairPaginas(
            de: url,
            senha: senha
        )

        // 2. Organização das linhas e identificação dos lançamentos
        await aoMudarEtapa?(.organizandoLinhas)

        let linhas = paginas.enumerated().flatMap { indice, fragmentos in
            ReconstrutorLinhas.reconstruir(
                fragmentos,
                pagina: indice + 1
            )
        }

        let segmentacao = segmentador.segmentar(linhas)

        guard !segmentacao.lancamentos.isEmpty else {
            throw ErroFatura.nenhumLancamento
        }

        // 3. Categorização
        await aoMudarEtapa?(.categorizando)

        let descricoesDeCompras = segmentacao.lancamentos
            .filter { $0.tipo == .compra }
            .map(\.descricao)

        let categorias = await categorizador.categorizar(
            descricoes: descricoesDeCompras
        )

        var despesas: [LancamentoFatura] = []
        var pagamentos: [LancamentoFatura] = []

        for var lancamento in segmentacao.lancamentos {

            switch lancamento.tipo {

            case .compra:
                lancamento.categoria =
                    categorias[lancamento.descricao.chaveEstabelecimento] ?? "Outros"

            case .estorno:
                lancamento.categoria = "Estornos"

            case .encargo:
                lancamento.categoria = "Encargos"

            case .pagamento:
                pagamentos.append(lancamento)
                continue
            }

            despesas.append(lancamento)
        }

        // 4. Reconciliação dos totais
        await aoMudarEtapa?(.verificando)

        let calculado = despesas.reduce(Decimal.zero) {
            $0 + $1.valorAssinado
        }

        let reconciliacao: Reconciliacao

        if segmentacao.totaisDeclarados.isEmpty {

            reconciliacao = .semTotalNoDocumento(
                calculado: calculado
            )

        } else if segmentacao.totaisDeclarados.contains(
            where: { abs($0 - calculado) <= 0.01 }
        ) {

            reconciliacao = .conciliada

        } else {

            reconciliacao = .divergente(
                calculado: calculado,
                declarados: segmentacao.totaisDeclarados
            )
        }

        // 5. Retorno do resultado
        return FaturaProcessada(
            lancamentos: despesas,
            pagamentos: pagamentos,
            reconciliacao: reconciliacao
        )
    }
}
 ⁠

---

### Arquivo: \⁠ ./Services/IdentificadorBancoService.swift\ ⁠
⁠ swift
//
//  IdentificadorBancoService.swift
//  MIB
//
//  Created by Lucas on 26/11/26.
//

import Foundation
import FoundationModels
import PDFKit

//Resultado da análise visual

@Generable
struct AnaliseVisualBanco {

    @Guide(description: """
    Nome da instituição financeira emissora identificada
    visualmente. Pode ser qualquer banco, fintech ou
    instituição financeira. Se não for possível identificar,
    retorne Não identificado.
    """)
    var nomeInstituicao: String
}

//Erros

enum ErroIdentificacaoBanco: LocalizedError {

    case modeloIndisponivel
    case pdfInvalido
    case pdfSemPaginas
    case imagemIndisponivel

    var errorDescription: String? {

        switch self {

        case .modeloIndisponivel:
            return "A Apple Intelligence não está disponível."

        case .pdfInvalido:
            return "Não foi possível abrir o PDF."

        case .pdfSemPaginas:
            return "O PDF não possui páginas."

        case .imagemIndisponivel:
            return "Não foi possível converter a página em imagem."
        }
    }
}

@MainActor
struct IdentificadorBancoService {

    private let modelo = SystemLanguageModel.default

    var disponivel: Bool {

        if case .available = modelo.availability {
            return true
        }

        return false
    }

    func identificarBanco(
        no pdfURL: URL
    ) async throws -> String {

        guard disponivel else {
            throw ErroIdentificacaoBanco.modeloIndisponivel
        }

        // Acessa o arquivo selecionado pelo usuário.

        let acessoConcedido =
            pdfURL.startAccessingSecurityScopedResource()

        defer {
            if acessoConcedido {
                pdfURL.stopAccessingSecurityScopedResource()
            }
        }

        // Abre o documento.

        guard let documento = PDFDocument(url: pdfURL) else {
            throw ErroIdentificacaoBanco.pdfInvalido
        }

        guard let primeiraPagina = documento.page(at: 0) else {
            throw ErroIdentificacaoBanco.pdfSemPaginas
        }

        // Converte a primeira pagina em imagem.

        let dimensoes = primeiraPagina.bounds(for: .mediaBox)

        guard dimensoes.width > 0,
              dimensoes.height > 0 else {
            throw ErroIdentificacaoBanco.imagemIndisponivel
        }

        let larguraImagem: CGFloat = 1600
        let proporcao = dimensoes.height / dimensoes.width

        let tamanhoImagem = CGSize(
            width: larguraImagem,
            height: larguraImagem * proporcao
        )

        let imagem = primeiraPagina.thumbnail(
            of: tamanhoImagem,
            for: .mediaBox
        )

        guard let imagemCG = imagem.cgImage else {
            throw ErroIdentificacaoBanco.imagemIndisponivel
        }

        // analise de imagem com Apple Intelligence

        let instrucoes = """

        Você é um especialista em reconhecimento visual
        de instituições financeiras.

        Sua tarefa é identificar a instituição emissora
        de uma fatura de cartão de crédito brasileira.

        PRIORIDADE DA ANÁLISE:

        1. Identifique visualmente a logomarca da instituição.
        2. Observe símbolos, desenhos, cores e tipografia.
        3. Utilize o nome escrito na logo como confirmação.
        4. Considere qualquer instituição financeira,
           mesmo que não seja uma instituição conhecida previamente.

        REGRAS IMPORTANTES:

        - Não utilize uma lista fechada de bancos.
        - Não confunda Visa, Mastercard ou outras bandeiras
          com a instituição emissora.
        - Não confunda logos de estabelecimentos comerciais
          com a logo do banco.
        - Não considere cores isoladamente como prova suficiente.
        - Não invente o nome da instituição.
        - Caso não consiga identificar a logo, retorne
          "Não identificado".

        """

        let sessao = LanguageModelSession(
            model: modelo,
            instructions: instrucoes
        )

        let resposta = try await sessao.respond(
            generating: AnaliseVisualBanco.self
        ) {

            """
            Analise visualmente a primeira página desta
            fatura de cartão de crédito.

            Identifique a instituição financeira emissora
            do documento e retorne apenas o nome dela.
            """

            Attachment(imagemCG)
        }

        return resposta.content.nomeInstituicao
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
 ⁠

---

### Arquivo: \⁠ ./Services/InterpretadorFaturaService.swift\ ⁠
⁠ swift
//
//  Interpretador.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import FoundationModels

enum ErroInterpretacao: LocalizedError {
    case modeloIndisponivel
    case textoVazio

    var errorDescription: String? {
        switch self {
        case .modeloIndisponivel:
            return "A Apple Intelligence não está disponível neste dispositivo."

        case .textoVazio:
            return "Não há texto da fatura para interpretar."
        }
    }
}

@MainActor
struct InterpretadorFaturaService {

    private let modelo = SystemLanguageModel.default

    var disponivel: Bool {
        if case .available = modelo.availability {
            return true
        }

        return false
    }


    func interpretar(
        texto: String
    ) async throws -> [LancamentoExtraido] {

        guard disponivel else {
            throw ErroInterpretacao.modeloIndisponivel
        }

        guard !texto.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw ErroInterpretacao.textoVazio
        }

        let instrucoes = """
        Você interpreta faturas brasileiras de cartão de crédito.

        Extraia todos os lançamentos financeiros presentes no documento.

        TIPOS DE LANÇAMENTO:
        - compra: compras e despesas realizadas no cartão.
        - estorno: devoluções, reembolsos ou cancelamentos de compras.
        - pagamento: pagamento realizado para quitar a fatura.
        - encargo: juros, multas e tarifas cobradas pelo banco.

        REGRAS IMPORTANTES:
        1. Uma compra comum deve ser classificada como "compra".
        2. Não confunda compras com estornos.
        3. Somente classifique como "estorno" quando o documento
           indicar claramente uma devolução, reembolso ou crédito.
        4. Compras do mesmo estabelecimento e valor podem ser
           transações diferentes. Preserve todas.
        5. Não interprete uma compra como estorno apenas porque
           existe outra compra semelhante.
        6. Para compras parceladas, use o valor da parcela atual.
        7. Preserve datas e descrições originais.
        8. Não invente lançamentos.
        9. Não inclua totais e subtotais da fatura como transações.

        REGRAS PARA VALORES:
        - Copie os valores exatamente como estão no documento.
        - Não converta reais para centavos.
        - Não arredonde nem altere os números.
        - Preserve os separadores decimais originais.
        - Não deduza valores ausentes.

        CATEGORIZAÇÃO:
        - Supermercados, restaurantes, cafeterias: Alimentação.
        - Uber, táxi, ônibus e transporte: Transporte.
        - Aluguel e despesas residenciais: Moradia.
        - Farmácias e serviços médicos: Saúde.
        - Lazer: cinema, shows, parques e atividades de entretenimento
          pagas individualmente.
        - Assinaturas: serviços contratados por assinatura,
          incluindo plataformas de streaming como Netflix,
          Spotify, Disney+ e outros serviços semelhantes.
        - Quando um serviço de entretenimento funcionar por
          assinatura, priorize a categoria "Assinaturas"
          em vez de "Lazer".
        - Estornos e reembolsos: Estornos.
        - Compras em lojas de roupas, papelaria, utensílios: Compras
        - Descrições desconhecidas: Outros.

        REGRAS DE CATEGORIAS:
        - Todo lançamento do tipo "estorno" deve receber
          obrigatoriamente a categoria "Estornos".
        - Um estabelecimento desconhecido deve ir para "Outros".
        - Não atribua categorias sem evidências suficientes.
        - Pagamentos que aparacem na fatura não representam novas despesas logo nao precisam estar presentes no relatório.

        REGRAS PARA COMPRAS PARCELADAS:
        - Identifique separadamente o número da parcela
          e o valor monetário da transação.
        - Expressões como "PARC 02/03" indicam a segunda
          parcela de um total de três parcelas.
        - O número da parcela não representa o valor da compra.
        - O valor monetário deve ser copiado exatamente
          do campo correspondente à transação.
        - Não utilize números presentes na descrição
          como valores financeiros.
        
        REGRAS DE EXTRAÇÃO:
        - Extraia cada linha de transação apenas uma vez.
        - Cada lançamento retornado deve corresponder a uma
          transação individual presente no documento.
        - Não repita transações já extraídas.
        - Não crie lançamentos adicionais para completar
          ou continuar uma sequência.
        - Preserve a correspondência original entre
          data, descrição e valor.
        - Nunca associe a data de uma transação
          ao estabelecimento de outra.
        - Não invente transações ausentes no documento.
        - Se houver duas compras idênticas em linhas
          diferentes do documento, preserve ambas.
        """

        // Uma sessão nova para cada interpretação.
        let sessao = LanguageModelSession(
            model: modelo,
            instructions: instrucoes
        )

        let inicio = ContinuousClock.now

        let resposta = try await sessao.respond(
            to: "Extraia os lançamentos desta fatura:\n\(texto)",
            generating: ResultadoFaturaIA.self
        )

        let duracao = inicio.duration(to: .now)

        print("Tempo de interpretação: \(duracao)")

        return resposta.content.lancamentos.map {
            corrigirLancamento($0)
        }
    }

    private func corrigirLancamento(
        _ lancamento: LancamentoExtraido
    ) -> LancamentoExtraido {

        var corrigido = lancamento

        let descricao = lancamento.descricao
            .folding(
                options: [
                    .diacriticInsensitive,
                    .caseInsensitive
                ],
                locale: Locale(identifier: "pt_BR")
            )
            .uppercased()

        if descricao.contains("ESTORNO") ||
           descricao.contains("REEMBOLSO") {

            corrigido.tipo = "estorno"
            corrigido.categoria = "Estornos"

        } else if descricao.contains("PAGAMENTO RECEBIDO") {

            corrigido.tipo = "pagamento"
            corrigido.categoria = "Outros"

        } else if corrigido.tipo == "estorno" {

            corrigido.categoria = "Estornos"
        }

        return corrigido
    }
}
 ⁠

---

