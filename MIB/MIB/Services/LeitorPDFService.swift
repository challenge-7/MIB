//
//  LeitorPDFService.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import Foundation
import PDFKit
import Vision

enum ErroLeituraPDF: LocalizedError {
    case documentoInvalido
    case textoNaoEncontrado
    case senhaNecessaria
    case semPaginas

    var errorDescription: String? {
        switch self {
        case .documentoInvalido: return "Não foi possível abrir o arquivo PDF."
        case .textoNaoEncontrado: return "O PDF não contém texto que possa ser extraído."
        case .senhaNecessaria: return "O PDF é protegido. Informe a senha correta."
        case .semPaginas: return "O PDF não possui páginas."
        }
    }
}

struct LeitorPDFService {

    // Mantido como estava.
    func extrairTexto(de url: URL) throws -> String {
        let acessoAutorizado = url.startAccessingSecurityScopedResource()
        defer { if acessoAutorizado { url.stopAccessingSecurityScopedResource() } }

        guard let documento = PDFDocument(url: url) else {
            throw ErroLeituraPDF.documentoInvalido
        }
        guard let texto = documento.string,
              !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ErroLeituraPDF.textoNaoEncontrado
        }
        return texto
    }

    /// Fragmentos de texto com posição, página a página.
    /// Páginas sem texto digital passam por OCR local (Vision).
    @concurrent
    func extrairPaginas(de url: URL, senha: String? = nil) async throws -> [[FragmentoTexto]] {
        let acessoAutorizado = url.startAccessingSecurityScopedResource()
        defer { if acessoAutorizado { url.stopAccessingSecurityScopedResource() } }

        guard let documento = PDFDocument(url: url) else {
            throw ErroLeituraPDF.documentoInvalido
        }
        if documento.isLocked {
            guard let senha, documento.unlock(withPassword: senha) else {
                throw ErroLeituraPDF.senhaNecessaria
            }
        }
        guard documento.pageCount > 0 else { throw ErroLeituraPDF.semPaginas }

        var paginas: [[FragmentoTexto]] = []
        for indice in 0..<documento.pageCount {
            try Task.checkCancellation()
            guard let pagina = documento.page(at: indice) else {
                paginas.append([])
                continue
            }
            var fragmentos = fragmentosDigitais(de: pagina)
            if fragmentos.isEmpty {
                fragmentos = try reconhecerTexto(em: pagina)
            }
            paginas.append(fragmentos)
        }
        return paginas
    }

    nonisolated private func fragmentosDigitais(de pagina: PDFPage) -> [FragmentoTexto] {
        let area = pagina.bounds(for: .mediaBox)
        guard let selecao = pagina.selection(for: area) else { return [] }

        return selecao.selectionsByLine().compactMap { linha in
            guard let texto = linha.string?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !texto.isEmpty else { return nil }
            return FragmentoTexto(texto: texto, caixa: linha.bounds(for: pagina))
        }
    }

    nonisolated private func reconhecerTexto(em pagina: PDFPage) throws -> [FragmentoTexto] {
        let area = pagina.bounds(for: .mediaBox)
        guard area.width > 0, area.height > 0 else { return [] }

        let largura: CGFloat = 2000
        let imagem = pagina.thumbnail(
            of: CGSize(width: largura, height: largura * area.height / area.width),
            for: .mediaBox
        )
        guard let cgImage = imagem.cgImage else { return [] }

        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.recognitionLanguages = ["pt-BR"]
        pedido.usesLanguageCorrection = false   // números e nomes de lojas

        try VNImageRequestHandler(cgImage: cgImage).perform([pedido])

        return (pedido.results ?? []).compactMap { observacao in
            guard let texto = observacao.topCandidates(1).first?.string else { return nil }
            return FragmentoTexto(texto: texto, caixa: observacao.boundingBox)
        }
    }
}
