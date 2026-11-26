//
//  Lancamento.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import SwiftData

@Model
final class Lancamento {

    var data: String
    var descricao: String
    var valorCentavos: Int
    var tipo: String
    var categoria: String

    init(
        data: String,
        descricao: String,
        valorCentavos: Int,
        tipo: String,
        categoria: String
    ) {
        self.data = data
        self.descricao = descricao
        self.valorCentavos = valorCentavos
        self.tipo = tipo
        self.categoria = categoria
    }
}
