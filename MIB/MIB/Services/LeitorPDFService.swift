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

        guard let texto = documento.string,
              !texto.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            throw ErroLeituraPDF.textoNaoEncontrado
        }

        return texto
    }
}
