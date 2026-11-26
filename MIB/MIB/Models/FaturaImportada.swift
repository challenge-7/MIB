//
//  FaturaImportada.swift
//  MIB
//
//  Created by Gabriel Groppo on 26/11/26.
//

import Foundation

struct FaturaImportada: Identifiable {

    let id = UUID()
    let nomeArquivo: String
    let textoExtraido: String
}
