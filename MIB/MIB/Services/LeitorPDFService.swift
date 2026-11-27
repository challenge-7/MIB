//
//  LeitorPDFService.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import PDFKit

enum ErroLeituraPDF: LocalizedError {

    case documentoInvalido
    case textoNaoEncontrado

    var errorDescription: String? {
        switch self {
        case .documentoInvalido:
            return "Não foi possível abrir o arquivo PDF."

        case .textoNaoEncontrado:
            return "O PDF não contém texto que possa ser extraído."
        }
    }
}

struct LeitorPDFService {

    func extrairTexto(de url: URL) throws -> String {

        let acessoAutorizado =
            url.startAccessingSecurityScopedResource()

        defer {
            if acessoAutorizado {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let documento = PDFDocument(url: url) else {
            throw ErroLeituraPDF.documentoInvalido
        }

        let texto = selecionarPaginasRelevantes(
            documento: documento
        )
        
        
        let textoOriginal = documento.string ?? ""

        print("===== DIAGNÓSTICO PDF =====")
        print("Páginas totais: \(documento.pageCount)")
        print("Caracteres originais: \(textoOriginal.count)")
        print("Caracteres filtrados: \(texto.count)")

        if !textoOriginal.isEmpty {
            let reducao = (
                1 - Double(texto.count) / Double(textoOriginal.count)
            ) * 100

            print(
                "Redução do texto: \(reducao.formatted(.number.precision(.fractionLength(1))))%"
            )
        }


        guard !texto.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {

            throw ErroLeituraPDF.textoNaoEncontrado
        }

        return texto
    }
}

private func selecionarPaginasRelevantes(
    documento: PDFDocument
) -> String {

    let indicadores = [
        "TRANSAÇÕES",
        "TRANSACOES",
        "LANÇAMENTOS",
        "LANCAMENTOS",
        "SUAS COMPRAS",
        "DESPESAS",
        "DETALHAMENTO DE COMPRAS"
    ]

    var paginasRelevantes: [String] = []

    for indice in 0..<documento.pageCount {

        guard let pagina = documento.page(at: indice),
              let texto = pagina.string else {
            continue
        }

        let textoMaiusculo = texto.uppercased()

        let contemTransacoes = indicadores.contains {
            textoMaiusculo.contains($0)
        }

        if contemTransacoes {
            paginasRelevantes.append(texto)
        }
    }

    guard !paginasRelevantes.isEmpty else {
        return documento.string ?? ""
    }

    return paginasRelevantes.joined(separator: "\n")
}

