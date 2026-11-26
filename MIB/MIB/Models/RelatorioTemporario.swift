//
//  RelatorioTemporario.swift
//  MIB
//
//  Created by Gabriel Groppo on 26/11/26.
//

import Foundation

struct LancamentoTemporario: Identifiable {

    let id: UUID

    var data: String
    var descricao: String
    var valorCentavos: Int
    var tipo: String
    var categoria: String
    var nomeArquivoOrigem: String

    init(
        id: UUID = UUID(),
        data: String,
        descricao: String,
        valorCentavos: Int,
        tipo: String,
        categoria: String,
        nomeArquivoOrigem: String
    ) {
        self.id = id
        self.data = data
        self.descricao = descricao
        self.valorCentavos = valorCentavos
        self.tipo = tipo
        self.categoria = categoria
        self.nomeArquivoOrigem = nomeArquivoOrigem
    }
}

struct RelatorioTemporario {

    var nome: String
    var lancamentos: [LancamentoTemporario]
}
