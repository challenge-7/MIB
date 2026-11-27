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
    case compra
    case estorno
    case pagamento
    case encargo
}

struct LancamentoFatura: Identifiable, Sendable {
    let id = UUID()
    var data: Date
    var descricao: String
    /// O valor é armazenado como magnitude positiva.
    /// O sinal é aplicado por `valorAssinado` conforme o tipo.
    var valor: Decimal
    var parcela: String?
    var tipo: TipoLancamento
    var categoria: String = "Outros"

    var valorAssinado: Decimal {
        tipo == .estorno ? -valor : valor
    }
}

/// Tipo semântico de um valor financeiro encontrado na fatura.
/// Somente `totalFatura` pode ser usado na reconciliação das despesas.
enum TipoTotalDeclarado: String, Sendable, Equatable {
    case totalFatura
    case limiteTotal
    case limiteDisponivel
    case pagamentoMinimo
    case subtotal
    case totalAnterior
    case outro
}

struct TotalDeclarado: Sendable, Equatable {
    let descricao: String
    let valor: Decimal
    let tipo: TipoTotalDeclarado
    let pagina: Int
}

enum Reconciliacao: Sendable {
    case conciliada
    case divergente(calculado: Decimal, declarados: [Decimal])
    case semTotalNoDocumento(calculado: Decimal)
}

struct FaturaProcessada: Sendable {
    /// Compras, estornos e encargos. Pagamentos ficam em propriedade separada.
    let lancamentos: [LancamentoFatura]
    let pagamentos: [LancamentoFatura]
    let reconciliacao: Reconciliacao

    var totalPorCategoria: [String: Decimal] {
        lancamentos.reduce(into: [:]) { resultado, item in
            resultado[item.categoria, default: .zero] += item.valorAssinado
        }
    }
}

extension String {
    var normalizado: String {
        folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "pt_BR")
        )
        .uppercased()
    }

    /// Chave do estabelecimento para consulta no cache de categorias.
    var chaveEstabelecimento: String {
        let letras = normalizado.unicodeScalars.map { escalar in
            CharacterSet.letters.contains(escalar) ? Character(escalar) : " "
        }

        return String(letras)
            .split(whereSeparator: \.isWhitespace)
            .filter { $0 != "PARC" && $0 != "PARCELA" }
            .joined(separator: " ")
    }
}
