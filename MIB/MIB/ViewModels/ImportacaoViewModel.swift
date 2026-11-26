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
