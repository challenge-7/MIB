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
