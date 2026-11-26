//
//  ConversorMonetario.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//


import Foundation

struct ConversorMonetario {

    static func converterParaCentavos(_ texto: String) -> Int? {

        let valorLimpo = texto
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formato = #"^-?(?:\d{1,3}(?:\.\d{3})+|\d+),\d{2}$"#

        guard valorLimpo.range(
            of: formato,
            options: .regularExpression
        ) != nil else {
            return nil
        }

        let valorNormalizado = valorLimpo
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard let valor = Decimal(
            string: valorNormalizado,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            return nil
        }

        let numero = NSDecimalNumber(decimal: valor * 100)
        let inteiro = numero.int64Value

        guard numero != .notANumber,
              numero == NSDecimalNumber(value: inteiro),
              inteiro != Int64.min else {
            return nil
        }

        return Int(exactly: inteiro)
    }
}
