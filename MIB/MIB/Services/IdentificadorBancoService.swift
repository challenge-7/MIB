//
//  IdentificadorBancoService.swift
//  MIB
//
//  Created by Lucas on 26/11/26.
//


import Foundation
import FoundationModels
import PDFKit

//Resultado da análise visual

@Generable
struct AnaliseVisualBanco {

    @Guide(description: """
    Nome da instituição financeira emissora identificada
    visualmente. Pode ser qualquer banco, fintech ou
    instituição financeira. Se não for possível identificar,
    retorne Não identificado.
    """)
    var nomeInstituicao: String
}

//Erros

enum ErroIdentificacaoBanco: LocalizedError {

    case modeloIndisponivel
    case pdfInvalido
    case pdfSemPaginas
    case imagemIndisponivel

    var errorDescription: String? {

        switch self {

        case .modeloIndisponivel:
            return "A Apple Intelligence não está disponível."

        case .pdfInvalido:
            return "Não foi possível abrir o PDF."

        case .pdfSemPaginas:
            return "O PDF não possui páginas."

        case .imagemIndisponivel:
            return "Não foi possível converter a página em imagem."
        }
    }
}

@MainActor
struct IdentificadorBancoService {

    private let modelo = SystemLanguageModel.default

    var disponivel: Bool {

        if case .available = modelo.availability {
            return true
        }

        return false
    }

    func identificarBanco(
        no pdfURL: URL
    ) async throws -> String {

        guard disponivel else {
            throw ErroIdentificacaoBanco.modeloIndisponivel
        }

        // Acessa o arquivo selecionado pelo usuário.

        let acessoConcedido =
            pdfURL.startAccessingSecurityScopedResource()

        defer {
            if acessoConcedido {
                pdfURL.stopAccessingSecurityScopedResource()
            }
        }

        // Abre o documento.

        guard let documento = PDFDocument(url: pdfURL) else {
            throw ErroIdentificacaoBanco.pdfInvalido
        }

        guard let primeiraPagina = documento.page(at: 0) else {
            throw ErroIdentificacaoBanco.pdfSemPaginas
        }

        // Converte a primeira pagina em imagem.

        let dimensoes = primeiraPagina.bounds(for: .mediaBox)

        guard dimensoes.width > 0,
              dimensoes.height > 0 else {
            throw ErroIdentificacaoBanco.imagemIndisponivel
        }

        let larguraImagem: CGFloat = 1600
        let proporcao = dimensoes.height / dimensoes.width

        let tamanhoImagem = CGSize(
            width: larguraImagem,
            height: larguraImagem * proporcao
        )

        let imagem = primeiraPagina.thumbnail(
            of: tamanhoImagem,
            for: .mediaBox
        )

        guard let imagemCG = imagem.cgImage else {
            throw ErroIdentificacaoBanco.imagemIndisponivel
        }

        // analise de imagem com Apple Intelligence

        let instrucoes = """

        Você é um especialista em reconhecimento visual
        de instituições financeiras.

        Sua tarefa é identificar a instituição emissora
        de uma fatura de cartão de crédito brasileira.

        PRIORIDADE DA ANÁLISE:

        1. Identifique visualmente a logomarca da instituição.
        2. Observe símbolos, desenhos, cores e tipografia.
        3. Utilize o nome escrito na logo como confirmação.
        4. Considere qualquer instituição financeira,
           mesmo que não seja uma instituição conhecida previamente.

        REGRAS IMPORTANTES:

        - Não utilize uma lista fechada de bancos.
        - Não confunda Visa, Mastercard ou outras bandeiras
          com a instituição emissora.
        - Não confunda logos de estabelecimentos comerciais
          com a logo do banco.
        - Não considere cores isoladamente como prova suficiente.
        - Não invente o nome da instituição.
        - Caso não consiga identificar a logo, retorne
          "Não identificado".

        """

        let sessao = LanguageModelSession(
            model: modelo,
            instructions: instrucoes
        )

        let resposta = try await sessao.respond(
            generating: AnaliseVisualBanco.self
        ) {

            """
            Analise visualmente a primeira página desta
            fatura de cartão de crédito.

            Identifique a instituição financeira emissora
            do documento e retorne apenas o nome dela.
            """

            Attachment(imagemCG)
        }

        return resposta.content.nomeInstituicao
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
