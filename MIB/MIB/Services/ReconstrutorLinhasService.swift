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
