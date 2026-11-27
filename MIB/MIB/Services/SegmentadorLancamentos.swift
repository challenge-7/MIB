//
//  Segmentador.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//
import Foundation

struct ResultadoSegmentacao: Sendable {
    var lancamentos: [LancamentoFatura]
    var totaisDeclarados: [TotalDeclarado]
}

/// Segmenta linhas de faturas sem depender de um banco específico.
/// Primeiro identifica informações financeiras (limites, mínimo, totais); depois
/// identifica transações. Isso evita tratar o limite do cartão como uma compra.
struct SegmentadorLancamentos {

    private let dataInicio = #/^(\d{2})\/(\d{2})(?:\/(\d{4}|\d{2}))?\s+/#

    /// Capturas: 1 = sinal negativo, 2 = valor brasileiro, 3 = indicador CR.
    private let valor = #/(?i)(-)?(?:R\$\s*)?((?:\d{1,3}(?:\.\d{3})+|\d+),\d{2})(?:\s*(CR)\b)?/#

    private let parcelaExplicita = #/(?i)\bPARC(?:ELA)?\.?\s*(\d{1,2})\s*\/\s*(\d{1,2})/#
    private let parcelaFinal = #/\b(\d{2})\/(\d{2})\s*$/#
    private let vencimento = #/(?i)vencimento.*?(\d{2})\/(\d{2})\/(\d{4})/#

    func segmentar(_ linhas: [LinhaPagina]) -> ResultadoSegmentacao {
        let referencia = mesEAnoReferencia(linhas)
        var lancamentos: [LancamentoFatura] = []
        var totais: [TotalDeclarado] = []
        var secao: TipoLancamento = .compra
        var anteriorFoiLancamento = false

        for linha in linhas {
            let texto = linha.texto
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !texto.isEmpty else { continue }

            // 1. Extrai totais e limites ANTES das transações.
            // Cada valor é associado ao rótulo imediatamente anterior a ele.
            // Isso também permite tratar linhas com mais de um valor na mesma linha.
            let totaisDaLinha = extrairTotais(de: linha)
            if !totaisDaLinha.isEmpty || tipoTotal(de: texto) != nil {
                totais.append(contentsOf: totaisDaLinha)
                anteriorFoiLancamento = false
                continue
            }

            // 2. Atualiza a seção quando encontra um cabeçalho sem valor monetário.
            if let novaSecao = secaoDe(texto) {
                secao = novaSecao
                anteriorFoiLancamento = false
                continue
            }

            // 3. Ignora informações que não representam transações.
            if ehInformacaoNaoTransacional(texto) {
                anteriorFoiLancamento = false
                continue
            }

            // 4. Tenta reconhecer uma transação.
            if let item = lancamento(
                de: texto,
                secao: secao,
                referencia: referencia
            ) {
                lancamentos.append(item)
                anteriorFoiLancamento = true
                continue
            }

            // 5. Trata descrições que foram quebradas em uma linha seguinte.
            if anteriorFoiLancamento,
               podeSerContinuacao(texto),
               var ultimo = lancamentos.popLast() {
                ultimo.descricao += " " + texto
                lancamentos.append(ultimo)
            }

            anteriorFoiLancamento = false
        }

        return ResultadoSegmentacao(
            lancamentos: lancamentos,
            totaisDeclarados: totais
        )
    }

    // MARK: - Identificação de totais e informações financeiras

    private func tipoTotal(de texto: String) -> TipoTotalDeclarado? {
        let t = texto.normalizado

        // A ordem importa: limite não pode ser interpretado como total da fatura.
        if t.contains("LIMITE DISPONIVEL") ||
            t.contains("CREDITO DISPONIVEL") ||
            t.contains("DISPONIVEL PARA COMPRAS") ||
            t.contains("DISPONIVEL") {
            return .limiteDisponivel
        }

        if t.contains("LIMITE") {
            return .limiteTotal
        }

        if t.contains("PAGAMENTO MINIMO") ||
            t.contains("VALOR MINIMO") ||
            t.contains("MINIMO A PAGAR") {
            return .pagamentoMinimo
        }

        if t.contains("FATURA ANTERIOR") ||
            t.contains("TOTAL ANTERIOR") ||
            t.contains("SALDO ANTERIOR") {
            return .totalAnterior
        }

        if t.contains("SUBTOTAL") ||
            t.contains("TOTAL DE COMPRAS") ||
            t.contains("TOTAL DE DESPESAS") ||
            t.contains("TOTAL DE LANCAMENTOS") {
            return .subtotal
        }

        if t.contains("TOTAL DA FATURA") ||
            t.contains("TOTAL DESTA FATURA") ||
            t.contains("TOTAL FATURA") ||
            t.contains("TOTAL A PAGAR") ||
            t.contains("VALOR TOTAL DA FATURA") ||
            t.contains("TOTAL DO MES") {
            return .totalFatura
        }

        // Outros totais são guardados para auditoria, mas nunca conciliados.
        if t.contains("TOTAL") {
            return .outro
        }

        return nil
    }

    private func extrairTotais(de linha: LinhaPagina) -> [TotalDeclarado] {
        let ocorrencias = linha.texto.matches(of: valor)
        guard !ocorrencias.isEmpty else { return [] }

        var resultado: [TotalDeclarado] = []
        var inicioDoRotulo = linha.texto.startIndex

        for ocorrencia in ocorrencias {
            let rotulo = String(linha.texto[inicioDoRotulo..<ocorrencia.range.lowerBound])

            if let tipo = tipoTotal(de: rotulo),
               let quantia = decimal(de: String(ocorrencia.output.2)) {
                resultado.append(
                    TotalDeclarado(
                        descricao: rotulo.trimmingCharacters(in: .whitespacesAndNewlines),
                        valor: quantia,
                        tipo: tipo,
                        pagina: linha.pagina
                    )
                )
            }

            inicioDoRotulo = ocorrencia.range.upperBound
        }

        return resultado
    }

    private func ehInformacaoNaoTransacional(_ texto: String) -> Bool {
        let t = texto.normalizado

        let marcadores = [
            "VENCIMENTO",
            "MELHOR DIA DE COMPRA",
            "FECHAMENTO DA FATURA",
            "ENCARGOS FINANCEIROS",
            "CUSTO EFETIVO TOTAL",
            "TAXA DE JUROS",
            "LIMITE DE CREDITO",
            "LIMITE TOTAL",
            "LIMITE",
            "DISPONIVEL",
            "LIMITE DISPONIVEL",
            "PAGAMENTO MINIMO",
            "PARCELAMENTO DE FATURA"
        ]

        return marcadores.contains(where: { t.contains($0) })
    }

    // MARK: - Identificação de transações

    private func lancamento(
        de texto: String,
        secao: TipoLancamento,
        referencia: (mes: Int, ano: Int)
    ) -> LancamentoFatura? {

        guard let dataMatch = texto.firstMatch(of: dataInicio),
              let dia = Int(dataMatch.output.1),
              let mes = Int(dataMatch.output.2),
              (1...31).contains(dia),
              (1...12).contains(mes)
        else {
            return nil
        }

        // Mantém a escolha do último valor da linha, mas somente depois de
        // excluir linhas de limite, totais, pagamento mínimo e outros metadados.
        let valores = texto.matches(of: valor)
        guard let ultimoValor = valores.last,
              ultimoValor.range.lowerBound >= dataMatch.range.upperBound,
              let magnitude = decimal(de: String(ultimoValor.output.2)) else {
            return nil
        }

        let ano: Int
        if let textoAno = dataMatch.output.3,
           let numero = Int(textoAno) {
            ano = textoAno.count == 2 ? 2000 + numero : numero
        } else {
            ano = mes > referencia.mes ? referencia.ano - 1 : referencia.ano
        }

        var componentes = DateComponents()
        componentes.day = dia
        componentes.month = mes
        componentes.year = ano

        let calendario = Calendar(identifier: .gregorian)
        guard let dataCompleta = calendario.date(from: componentes),
              calendario.component(.day, from: dataCompleta) == dia,
              calendario.component(.month, from: dataCompleta) == mes,
              calendario.component(.year, from: dataCompleta) == ano else {
            return nil
        }

        let descricaoBruta = texto[dataMatch.range.upperBound..<ultimoValor.range.lowerBound]
        let descricao = descricaoBruta
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !descricao.isEmpty else { return nil }

        let credito = ultimoValor.output.1 != nil || ultimoValor.output.3 != nil

        return LancamentoFatura(
            data: dataCompleta,
            descricao: descricao,
            valor: magnitude,
            parcela: parcela(em: descricao),
            tipo: tipo(
                descricao: descricao,
                secao: secao,
                credito: credito
            )
        )
    }

    private func tipo(
        descricao: String,
        secao: TipoLancamento,
        credito: Bool
    ) -> TipoLancamento {
        let d = descricao.normalizado

        if d.contains("PAGAMENTO RECEBIDO") ||
            d.contains("PAGAMENTO EFETUADO") ||
            d.contains("PAGAMENTO DE FATURA") ||
            d.contains("PAGTO") {
            return .pagamento
        }

        if d.contains("ESTORNO") ||
            d.contains("REEMBOLSO") ||
            d.contains("DEVOLUCAO") {
            return .estorno
        }

        if ["JUROS", "MULTA", "IOF", "ANUIDADE", "TARIFA", "ENCARGO"]
            .contains(where: d.contains) {
            return .encargo
        }

        if secao == .pagamento { return .pagamento }
        if credito { return .estorno }

        return secao == .estorno || secao == .encargo ? secao : .compra
    }

    private func parcela(em descricao: String) -> String? {
        if let match = descricao.firstMatch(of: parcelaExplicita) {
            return "\(match.output.1)/\(match.output.2)"
        }

        if let match = descricao.firstMatch(of: parcelaFinal) {
            return "\(match.output.1)/\(match.output.2)"
        }

        return nil
    }

    // MARK: - Seções, continuações e referência de data

    private func secaoDe(_ texto: String) -> TipoLancamento? {
        guard texto.count <= 70,
              texto.matches(of: valor).isEmpty else {
            return nil
        }

        let t = texto.normalizado

        if t.contains("PAGAMENTO") { return .pagamento }

        if t.contains("ESTORNO") ||
            t.contains("REEMBOLSO") ||
            t.contains("DEVOLUC") {
            return .estorno
        }

        if ["ENCARGO", "JUROS", "MULTA", "TARIFA", "ANUIDADE", "IOF"]
            .contains(where: t.contains) {
            return .encargo
        }

        if ["COMPRAS", "TRANSAC", "LANCAMENTOS", "DESPESAS"]
            .contains(where: t.contains) {
            return .compra
        }

        return nil
    }

    private func podeSerContinuacao(_ texto: String) -> Bool {
        texto.count <= 50 &&
            !texto.contains(where: \.isNumber) &&
            texto.matches(of: valor).isEmpty &&
            tipoTotal(de: texto) == nil &&
            !ehInformacaoNaoTransacional(texto)
    }

    private func mesEAnoReferencia(
        _ linhas: [LinhaPagina]
    ) -> (mes: Int, ano: Int) {
        for linha in linhas {
            if let match = linha.texto.firstMatch(of: vencimento),
               let mes = Int(match.output.2),
               let ano = Int(match.output.3) {
                return (mes, ano)
            }
        }

        let componentes = Calendar(identifier: .gregorian)
            .dateComponents([.month, .year], from: .now)

        return (componentes.month ?? 1, componentes.year ?? 2026)
    }

    private func decimal(de texto: String) -> Decimal? {
        let normalizado = texto
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")

        return Decimal(
            string: normalizado,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
