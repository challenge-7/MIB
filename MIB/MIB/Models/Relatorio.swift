//
//  Relatorio.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import SwiftData

@Model
final class Relatorio {

    var nome: String
    var dataCriacao: Date

    @Relationship(deleteRule: .cascade)
    var lancamentos: [Lancamento] = []

    init(
        nome: String,
        dataCriacao: Date = .now,
        lancamentos: [Lancamento] = []
    ) {
        self.nome = nome
        self.dataCriacao = dataCriacao
        self.lancamentos = lancamentos
    }
}
