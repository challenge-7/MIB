//
//  Fatura.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import SwiftData

@Model
final class FaturaSalva {

    var nomeArquivo: String
    var dataImportacao: Date

    @Relationship(deleteRule: .cascade)
    var lancamentos: [Lancamento] = []

    init(
        nomeArquivo: String,
        dataImportacao: Date = .now,
        lancamentos: [Lancamento] = []
    ) {
        self.nomeArquivo = nomeArquivo
        self.dataImportacao = dataImportacao
        self.lancamentos = lancamentos
    }
}
