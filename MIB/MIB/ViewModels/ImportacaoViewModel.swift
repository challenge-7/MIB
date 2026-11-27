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

                
                let inicio = Date()

                print("⏱️ Iniciando interpretação: \(fatura.nomeArquivo)")

                
                let divisor = DivisorFaturaService()

                let blocos = divisor.dividirTexto(
                    fatura.textoExtraido
                )

                print("===== TESTE DE DIVISÃO =====")
                print("Fatura: \(fatura.nomeArquivo)")
                print("Quantidade de blocos: \(blocos.count)")

                for (indice, bloco) in blocos.enumerated() {
                    print("""
                    ----- BLOCO \(indice + 1) -----
                    Caracteres: \(bloco.count)
                    \(bloco)
                    """)
                }
                
                let linhas = fatura.textoExtraido.components(
                    separatedBy: .newlines
                )

                let linhasComData = linhas.filter { linha in

                    let texto = linha.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                    return texto.range(
                        of: #"^\d{2}/\d{2}(?:/\d{4})?\s+"#,
                        options: .regularExpression
                    ) != nil
                }

                print("===== IDENTIFICAÇÃO DE TRANSAÇÕES =====")
                print("Linhas iniciadas por data: \(linhasComData.count)")

                
                var textoParaAgrupar = fatura.textoExtraido

                if let intervalo = textoParaAgrupar.range(
                    of: "Compras parceladas - próximas faturas",
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) {
                    textoParaAgrupar = String(
                        textoParaAgrupar[..<intervalo.lowerBound]
                    )
                }

                let grupos = divisor.agruparLinhasPorTransacao(
                    textoParaAgrupar
                )

                print("Grupos após remover parcelas futuras: \(grupos.count)")


                print("===== AGRUPAMENTO =====")
                print("Grupos encontrados: \(grupos.count)")

                for (indice, grupo) in grupos.enumerated() {

                    let linhas = grupo.components(
                        separatedBy: .newlines
                    )

                    if linhas.count != 2 {

                        print("===== GRUPO \(indice + 1) =====")
                        print("Quantidade de linhas: \(linhas.count)")
                        print(grupo)
                    }
                }

               
                let gruposParaAnalise = grupos.filter { grupo in

                    let texto = grupo.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "pt_BR")
                    )

                    return !texto.contains("pagamento via conta")
                }

                let lotes = divisor.criarLotes(
                    grupos: gruposParaAnalise
                )

                
                print("===== CONFERÊNCIA DOS LOTES =====")

                var totalGrupos = 0

                for (indice, lote) in lotes.enumerated() {

                    let quantidadeGrupos = lote.components(
                        separatedBy: "\n\n"
                    ).count

                    totalGrupos += quantidadeGrupos

                    print(
                        "Lote \(indice + 1): " +
                        "\(quantidadeGrupos) grupos enviados"
                    )
                }

                print("Total de grupos enviados: \(totalGrupos)")

                
                print("===== VALIDAÇÃO DOS LOTES =====")
                print("Grupos originais: \(grupos.count)")
                print("Grupos para análise: \(gruposParaAnalise.count)")
                print("Lotes: \(lotes.count)")


                print("===== LOTES PARA A IA =====")
                print("Quantidade de lotes: \(lotes.count)")

                for (indice, lote) in lotes.enumerated() {
                    print(
                        "Lote \(indice + 1): \(lote.count) caracteres"
                    )
                }
                
                let linhasOriginais = fatura.textoExtraido.components(
                    separatedBy: .newlines
                )

                for (indice, linha) in linhasOriginais.enumerated() {

                    if linha.localizedCaseInsensitiveContains("Repasse de IOF") {

                        print("===== DIAGNÓSTICO IOF =====")

                        let inicio = max(0, indice - 1)
                        let fim = min(linhasOriginais.count, indice + 5)

                        for posicao in inicio..<fim {
                            print("[\(posicao)] \(linhasOriginais[posicao])")
                        }
                    }
                }

                let iofInternacional = divisor.extrairIOFInternacional(
                    fatura.textoExtraido
                )

                print("===== IOF IDENTIFICADO =====")
                print("Valor: \(iofInternacional ?? "Não encontrado")")
                
                

                print("===== TESTE DE MÚLTIPLOS LOTES =====")

                var todosExtraidos: [LancamentoExtraido] = []

                let inicioTotal = Date()

                for (indice, lote) in lotes.enumerated() {

                    print("Iniciando lote \(indice + 1) de \(lotes.count)")
                    print("Caracteres: \(lote.count)")

                    let inicioLote = Date()

                    let resultado = try await interpretador.interpretar(
                        texto: lote
                    )

                    let tempoLote = Date().timeIntervalSince(inicioLote)

                    print(
                        "Lote \(indice + 1) concluído em " +
                        "\(String(format: "%.2f", tempoLote)) segundos"
                    )

                    print("Lançamentos: \(resultado.count)")

                    todosExtraidos.append(contentsOf: resultado)
                }

                let tempoTotal = Date().timeIntervalSince(inicioTotal)

                print("===== RESULTADO CONSOLIDADO =====")
                print("Total de lançamentos: \(todosExtraidos.count)")
                print(
                    "Tempo total: " +
                    "\(String(format: "%.2f", tempoTotal)) segundos"
                )

                let totalCentavos = todosExtraidos.reduce(0) { soma, item in

                    guard let valor = ConversorMonetario.converterParaCentavos(
                        item.valorOriginal
                    ) else {
                        return soma
                    }

                    switch item.tipo {
                    case "compra", "encargo":
                        return soma + abs(valor)
                    case "estorno":
                        return soma - abs(valor)
                    default:
                        return soma
                    }
                }

                print(
                    "Total extraído sem IOF complementar: " +
                    String(format: "R$ %.2f", Double(totalCentavos) / 100)
                )

                return


                return

                
                return
                
                let extraidos = try await interpretador.interpretar(
                    texto: fatura.textoExtraido
                )

                let tempo = Date().timeIntervalSince(inicio)

                print("✅ Fatura: \(fatura.nomeArquivo)")
                print("⏱️ Tempo de interpretação: \(tempo) segundos")
                print("📄 Lançamentos extraídos: \(extraidos.count)")

                
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
