//
//  DivisorFaturaService.swift
//  MIB
//
//  Created by Gabriel Groppo on 27/11/26.
//

import Foundation

struct DivisorFaturaService {

    func dividirTexto(
        _ texto: String,
        limiteCaracteres: Int = 1800
    ) -> [String] {

        guard limiteCaracteres > 0 else {
            return []
        }

        let linhas = texto.components(separatedBy: .newlines)

        var blocos: [String] = []
        var blocoAtual = ""

        for linha in linhas {

            let novaLinha = blocoAtual.isEmpty
                ? linha
                : "\n" + linha

            if blocoAtual.count + novaLinha.count > limiteCaracteres,
               !blocoAtual.isEmpty {

                blocos.append(blocoAtual)
                blocoAtual = linha

            } else {
                blocoAtual += novaLinha
            }
        }

        if !blocoAtual.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            blocos.append(blocoAtual)
        }

        return blocos
    }
    
    func agruparLinhasPorTransacao(
        _ texto: String
    ) -> [String] {

        let linhas = texto.components(separatedBy: .newlines)

        var grupos: [String] = []
        var grupoAtual: [String] = []

        for linha in linhas {

            let linhaLimpa = linha.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !linhaLimpa.isEmpty,
                  linhaLimpa != ".",
                  linhaLimpa != "1" else {
                continue
            }

            let iniciaComData = linhaLimpa.range(
                of: #"^\d{2}/\d{2}(?:/\d{4})?\s+"#,
                options: .regularExpression
            ) != nil

            if iniciaComData {

                if !grupoAtual.isEmpty {
                    grupos.append(
                        grupoAtual.joined(separator: "\n")
                    )
                }

                grupoAtual = [linhaLimpa]

            
            } else if !grupoAtual.isEmpty {

                let texto = linhaLimpa.folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "pt_BR")
                )

                let marcadores = [
                    "lancamentos no cartao",
                    "lancamentos internacionais",
                    "lancamentos: compras e saques",
                    "total dos pagamentos",
                    "total transacoes inter.",
                    "total dos lancamentos atuais",
                    "continua...",
                    "data estabelecimento"
                ]

                let inicioDeOutraSecao = marcadores.contains {
                    texto.hasPrefix($0)
                }

                if inicioDeOutraSecao {

                    grupos.append(
                        grupoAtual.joined(separator: "\n")
                    )

                    grupoAtual = []

                } else {
                    grupoAtual.append(linhaLimpa)
                }
            }

        }

        if !grupoAtual.isEmpty {
            grupos.append(
                grupoAtual.joined(separator: "\n")
            )
        }

        return grupos
    }
    
    
    func extrairIOFInternacional(
        _ texto: String
    ) -> String? {

        let linhas = texto.components(
            separatedBy: .newlines
        )

        for (indice, linha) in linhas.enumerated() {

            let linhaNormalizada = linha.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "pt_BR")
            )

            if linhaNormalizada.contains("repasse de iof") {

                let proximoIndice = indice + 1

                guard proximoIndice < linhas.count else {
                    return nil
                }

                let valor = linhas[proximoIndice]
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let formatoMonetario = #"^\d{1,3}(?:\.\d{3})*,\d{2}$"#

                guard valor.range(
                    of: formatoMonetario,
                    options: .regularExpression
                ) != nil else {
                    return nil
                }

                return valor
            }
        }

        return nil
    }
    
    func criarLotes(
        grupos: [String],
        limiteCaracteres: Int = 1500
    ) -> [String] {

        guard limiteCaracteres > 0 else {
            return []
        }

        var lotes: [String] = []
        var loteAtual = ""

        for grupo in grupos {

            let separador = loteAtual.isEmpty ? "" : "\n\n"

            let tamanhoNovo = loteAtual.count
                + separador.count
                + grupo.count

            if tamanhoNovo > limiteCaracteres,
               !loteAtual.isEmpty {

                lotes.append(loteAtual)
                loteAtual = grupo

            } else {

                loteAtual += separador + grupo
            }
        }

        if !loteAtual.isEmpty {
            lotes.append(loteAtual)
        }

        return lotes
    }
}
