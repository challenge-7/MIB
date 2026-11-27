//
//  CategorizadorService.swift
//  MIB
//
//  Created by Lucas on 27/11/26.
//
import Foundation
import FoundationModels

enum CategoriaGasto: String, CaseIterable, Sendable {
    case alimentacao = "Alimentação"
    case transporte = "Transporte"
    case moradia = "Moradia"
    case saude = "Saúde"
    case lazer = "Lazer"
    case assinaturas = "Assinaturas"
    case compras = "Compras"
    case outros = "Outros"
}

@Generable
struct ItemCategorizado {
    @Guide(description: "Índice inteiro do estabelecimento na lista recebida, começando em zero.")
    var indice: Int

    @Guide(.anyOf([
        "Alimentação",
        "Transporte",
        "Moradia",
        "Saúde",
        "Lazer",
        "Assinaturas",
        "Compras",
        "Outros"
    ]))
    var categoria: String
}

@Generable
struct ResultadoCategorizacao {
    @Guide(description: "Retorne uma classificação para cada índice recebido. Não altere nem invente índices.")
    var itens: [ItemCategorizado]
}

/// Cache local de estabelecimento -> categoria.
/// A chave V2 evita reutilizar classificações gravadas pelo categorizador antigo.
actor CacheCategorias {
    private let chaveDefaults = "cacheCategoriasV2"
    private var mapa: [String: String]

    init() {
        mapa = UserDefaults.standard.dictionary(forKey: chaveDefaults) as? [String: String] ?? [:]
    }

    func categoria(para chave: String) -> String? {
        mapa[chave]
    }

    func salvar(_ novos: [String: String]) {
        guard !novos.isEmpty else { return }
        mapa.merge(novos) { _, novaCategoria in novaCategoria }
        UserDefaults.standard.set(mapa, forKey: chaveDefaults)
    }

    /// Use este método quando o usuário corrigir manualmente uma categoria.
    func corrigir(descricao: String, categoria: String) {
        let chave = descricao.chaveEstabelecimento
        guard !chave.isEmpty,
              CategoriaGasto.allCases.map(\.rawValue).contains(categoria) else {
            return
        }
        salvar([chave: categoria])
    }
}

struct CategorizadorService {
    let cache: CacheCategorias
    private let tamanhoLote = 10

    private let instrucoes = """
    Você categoriza estabelecimentos encontrados em faturas de cartão brasileiras.

    Sua tarefa é classificar cada descrição em UMA das categorias permitidas.
    Use apenas evidências presentes no nome do estabelecimento.
    Não invente o ramo de atividade de nomes desconhecidos.

    CATEGORIAS:
    - Alimentação: supermercados, mercados, restaurantes, lanchonetes, padarias,
      cafeterias, delivery de comida e lojas de alimentos.
    - Transporte: corridas de aplicativo, táxi, ônibus, combustível, pedágio,
      estacionamento e transporte público.
    - Moradia: aluguel, condomínio e serviços residenciais.
    - Saúde: farmácias, hospitais, clínicas, laboratórios e serviços médicos.
    - Lazer: cinema, shows, parques, jogos e entretenimento comprado individualmente.
    - Assinaturas: Netflix, Spotify, Disney+, serviços recorrentes e streaming.
    - Compras: roupas, calçados, papelaria, eletrônicos e utensílios.
    - Outros: descrição ambígua, intermediador de pagamento ou evidência insuficiente.

    REGRAS IMPORTANTES:
    1. "MERCADOPAGO", "MP*", "PAG*", "PAY*" ou nome de intermediador,
       isoladamente, não identifica o produto comprado. Use Outros.
    2. Não classifique UBER EATS como Transporte; é Alimentação.
    3. Não classifique um estabelecimento como supermercado apenas porque
       seu nome contém a palavra "market" sem evidência suficiente.
    4. Não confunda bandeira de cartão, banco ou processador com estabelecimento.
    5. Se estiver em dúvida, escolha Outros.
    6. Preserve exatamente os índices recebidos, começando em zero.
    """

    /// Retorna um mapa chaveEstabelecimento -> categoria.
    func categorizar(descricoes: [String]) async -> [String: String] {
        var resultado: [String: String] = [:]
        var pendentes: [(chave: String, descricao: String)] = []
        var vistos = Set<String>()

        for descricao in descricoes {
            let chave = descricao.chaveEstabelecimento
            guard !chave.isEmpty,
                  vistos.insert(chave).inserted else {
                continue
            }

            // Primeiro respeita categorias já corrigidas ou armazenadas.
            if let existente = await cache.categoria(para: chave) {
                resultado[chave] = existente
                continue
            }

            // Regras locais só são usadas quando o nome é uma evidência forte.
            if let categoria = categoriaConhecida(para: chave) {
                resultado[chave] = categoria
                await cache.salvar([chave: categoria])
                continue
            }

            pendentes.append((chave: chave, descricao: descricao))
        }

        guard !pendentes.isEmpty else { return resultado }

        for inicio in stride(from: 0, to: pendentes.count, by: tamanhoLote) {
            let fim = min(inicio + tamanhoLote, pendentes.count)
            let lote = Array(pendentes[inicio..<fim])

            do {
                let obtidas = try await categorizarLote(
                    lote.map(\.descricao)
                )

                var novasParaCache: [String: String] = [:]

                for (indice, item) in lote.enumerated() {
                    if let categoria = obtidas[indice] {
                        resultado[item.chave] = categoria
                        novasParaCache[item.chave] = categoria
                    } else {
                        // Resposta ausente ou inválida não é tratada como certeza.
                        resultado[item.chave] = CategoriaGasto.outros.rawValue
                    }
                }

                await cache.salvar(novasParaCache)

            } catch {
                // Uma falha da IA não interrompe a leitura da fatura.
                // Itens não reconhecidos ficam em Outros e não entram no cache.
                for item in lote {
                    resultado[item.chave] = CategoriaGasto.outros.rawValue
                }
                print("Falha ao categorizar lote: \(error.localizedDescription)")
            }
        }

        return resultado
    }

    private func categoriaConhecida(para chave: String) -> String? {
        let nome = chave.normalizado

        // Ordem específica primeiro: Uber Eats não pode cair em Transporte.
        if contem(nome, algum: ["UBER EATS", "IFOOD", "SUPERMERCADO", "ATACADAO", "ASSAI", "CARREFOUR", "PAO DE ACUCAR", "HORTIFRUTI", "PADARIA", "RESTAURANTE", "LANCHONETE", "PIZZARIA", "MCDONALDS", "BURGER KING", "STARBUCKS"]) {
            return CategoriaGasto.alimentacao.rawValue
        }

        if contem(nome, algum: ["NETFLIX", "SPOTIFY", "DISNEY PLUS", "DISNEY", "HBO MAX", "MAX STREAMING", "GLOBOPLAY", "DEEZER", "PARAMOUNT PLUS", "AMAZON PRIME VIDEO"]) {
            return CategoriaGasto.assinaturas.rawValue
        }

        if contem(nome, algum: ["DROGASIL", "DROGA RAIA", "DROGARIA SAO PAULO", "DROGARIA PACHECO", "PANVEL", "FARMACIA", "HOSPITAL", "CLINICA MEDICA", "LABORATORIO"]) {
            return CategoriaGasto.saude.rawValue
        }

        if contem(nome, algum: ["UBER TRIP", "UBER *TRIP", "99APP", "99 POP", "POSTO IPIRANGA", "POSTO SHELL", "POSTO BR", "SEM PARAR", "ESTACIONAMENTO", "PEDAGIO"]) {
            return CategoriaGasto.transporte.rawValue
        }

        if contem(nome, algum: ["RENNER", "RIACHUELO", "C A", "ZARA", "NIKE STORE", "ADIDAS STORE", "MAGAZINE LUIZA", "LEROY MERLIN", "KALUNGA"]) {
            return CategoriaGasto.compras.rawValue
        }

        return nil
    }

    private func contem(_ texto: String, algum termos: [String]) -> Bool {
        termos.contains { texto.contains($0.normalizado) }
    }

    private func categorizarLote(
        _ descricoes: [String]
    ) async throws -> [Int: String] {
        let sessao = LanguageModelSession(
            model: .default,
            instructions: instrucoes
        )

        let lista = descricoes.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")

        let resposta = try await sessao.respond(
            to: "Classifique cada estabelecimento da lista.\n\(lista)",
            generating: ResultadoCategorizacao.self,
            options: GenerationOptions(sampling: .greedy)
        )

        let categoriasValidas = Set(CategoriaGasto.allCases.map(\.rawValue))
        var resultado: [Int: String] = [:]

        for item in resposta.content.itens {
            guard descricoes.indices.contains(item.indice),
                  categoriasValidas.contains(item.categoria),
                  resultado[item.indice] == nil else {
                continue
            }

            resultado[item.indice] = item.categoria
        }

        return resultado
    }
}
