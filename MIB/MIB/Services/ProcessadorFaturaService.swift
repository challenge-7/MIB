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

        try Task.checkCancellation()
        await aoMudarEtapa?(.lendoPDF)

        let paginas = try await leitor.extrairPaginas(
            de: url,
            senha: senha
        )

        try Task.checkCancellation()
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

        try Task.checkCancellation()
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
                    categorias[lancamento.descricao.chaveEstabelecimento] ?? CategoriaGasto.outros.rawValue

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

        try Task.checkCancellation()
        await aoMudarEtapa?(.verificando)

        // Só totais com classificação explícita de total da fatura entram na comparação.
        // Limite, pagamento mínimo, subtotais e totais anteriores são descartados aqui.
        let totaisValidos = segmentacao.totaisDeclarados
            .filter { $0.tipo == .totalFatura }
            .map(\.valor)

        let calculado = despesas.reduce(Decimal.zero) {
            $0 + $1.valorAssinado
        }

        let reconciliacao: Reconciliacao

        if totaisValidos.isEmpty {
            reconciliacao = .semTotalNoDocumento(
                calculado: calculado
            )
        } else if totaisValidos.contains(
            where: { abs($0 - calculado) <= Decimal(string: "0.01")! }
        ) {
            reconciliacao = .conciliada
        } else {
            reconciliacao = .divergente(
                calculado: calculado,
                declarados: totaisValidos
            )
        }

        return FaturaProcessada(
            lancamentos: despesas,
            pagamentos: pagamentos,
            reconciliacao: reconciliacao
        )
    }
}
