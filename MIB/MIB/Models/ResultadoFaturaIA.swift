//
//  ResultadoFaturaIA.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import FoundationModels

@Generable
struct LancamentoExtraido {

    @Guide(description: "Data da transação no formato DD/MM/AAAA")
    var data: String

    @Guide(description: "Descrição original do lançamento")
    var descricao: String

    @Guide(description: """
    Copie o valor monetário exatamente como aparece
    na fatura, sem realizar cálculos ou conversões.
    Exemplos: 185,90; 32,50; -48,70.
    Não confunda números de parcelas com valores.
    """)
    var valorOriginal: String

    @Guide(.anyOf([
        "compra",
        "estorno",
        "pagamento",
        "encargo"
    ]))
    var tipo: String

    @Guide(.anyOf([
        "Alimentação",
        "Compras",
        "Transporte",
        "Moradia",
        "Saúde",
        "Lazer",
        "Assinaturas",
        "Estornos",
        "Outros"
    ]))
    var categoria: String
}

@Generable
struct ResultadoFaturaIA {

    @Guide(description: """
    Todos os lançamentos financeiros individuais
    encontrados na fatura.
    Não inclua totais ou subtotais.
    """)
    var lancamentos: [LancamentoExtraido]
}
