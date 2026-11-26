//
//  ImportacaoViewModel.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class ImportacaoViewModel: ObservableObject {

    @Published private(set) var nomeArquivo: String?
    @Published private(set) var textoPDF = ""
    @Published private(set) var mensagem = "Selecione uma fatura PDF."
    @Published private(set) var processando = false
    @Published private(set) var faturaSalva: FaturaSalva?

    private let leitorPDF = LeitorPDFService()
    private let interpretador = InterpretadorFaturaService()

    func importarPDF(de url: URL) {

        guard !processando else {
            return
        }

        do {
            let texto = try leitorPDF.extrairTexto(de: url)

            nomeArquivo = url.lastPathComponent
            textoPDF = texto
            faturaSalva = nil

            mensagem = "Fatura importada com sucesso."

        } catch {
            nomeArquivo = nil
            textoPDF = ""
            faturaSalva = nil

            mensagem = "Erro ao importar: \(error.localizedDescription)"
        }
    }

    func analisarESalvar(contexto: ModelContext) async {

        guard !processando else {
            return
        }

        guard let nomeArquivo = nomeArquivo,
              !textoPDF.isEmpty else {
            mensagem = "Importe uma fatura antes de analisar."
            return
        }

        processando = true
        faturaSalva = nil

        defer {
            processando = false
        }

        mensagem = "Interpretando fatura com Apple Intelligence..."

        do {

            // 1. Solicitar a interpretação
            let lancamentosExtraidos = try await interpretador.interpretar(
                texto: textoPDF
            )

            guard !lancamentosExtraidos.isEmpty else {
                mensagem = "Nenhum lançamento foi identificado."
                return
            }

            // 2. Converter os lançamentos
            var lancamentos: [Lancamento] = []

            for item in lancamentosExtraidos {

                guard let centavos = ConversorMonetario.converterParaCentavos(
                    item.valorOriginal
                ) else {
                    mensagem = """
                    Valor inválido no lançamento:
                    \(item.descricao) — \(item.valorOriginal)

                    A fatura não foi salva.
                    """
                    return
                }

                // O valor armazenado representa a magnitude.
                // O tipo define se é compra, estorno ou pagamento.
                let valorAbsoluto = centavos < 0
                    ? -centavos
                    : centavos

                let lancamento = Lancamento(
                    data: item.data,
                    descricao: item.descricao,
                    valorCentavos: valorAbsoluto,
                    tipo: item.tipo,
                    categoria: item.categoria
                )

                lancamentos.append(lancamento)
            }

            // 3. Criar a fatura
            let novaFatura = FaturaSalva(
                nomeArquivo: nomeArquivo,
                lancamentos: lancamentos
            )

            // 4. Persistir no SwiftData
            contexto.insert(novaFatura)

            do {
                try contexto.save()
            } catch {
                contexto.delete(novaFatura)
                throw error
            }

            // 5. Informar o resultado à interface
            faturaSalva = novaFatura

            mensagem = """
            Fatura analisada e salva com sucesso!
            \(lancamentos.count) lançamentos identificados.
            """

        } catch {
            mensagem = "Erro na análise: \(error.localizedDescription)"
        }
    }
}
