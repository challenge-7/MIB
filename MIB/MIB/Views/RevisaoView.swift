//
//  RevisaoView.swift
//  MIB
//
//  Created by Gabriel Groppo on 26/11/26.
//

import SwiftUI

struct RevisaoView: View {

    @ObservedObject var viewModel: ImportacaoViewModel

    private let categorias = [
        "Alimentação",
        "Transporte",
        "Moradia",
        "Saúde",
        "Lazer",
        "Compras",
        "Assinaturas",
        "Educação",
        "Estornos",
        "Outros"
    ]


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("Revisar lançamentos")
                    .font(.title2.bold())

                Text("""
                Confira as categorias e os tipos de lançamento
                identificados pela Apple Intelligence.
                """)
                .foregroundStyle(.secondary)

                if let relatorio = viewModel.relatorioTemporario {

                    TextField(
                        "Nome do relatório",
                        text: Binding(
                            get: {
                                viewModel.relatorioTemporario?.nome ?? ""
                            },
                            set: {
                                viewModel.atualizarNome($0)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    ForEach(relatorio.lancamentos) { item in

                        VStack(alignment: .leading, spacing: 12) {

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.descricao)
                                        .font(.headline)

                                    Text(item.data)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(formatarReais(item.valorCentavos))
                                    .font(.headline)
                            }

                            Text(item.nomeArquivoOrigem)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                        
                            Picker(
                                "Categoria",
                                selection: Binding(
                                    get: {
                                        viewModel.relatorioTemporario?
                                            .lancamentos.first {
                                                $0.id == item.id
                                            }?.categoria ?? item.categoria
                                    },
                                    set: {
                                        viewModel.atualizarCategoria(
                                            id: item.id,
                                            categoria: $0
                                        )
                                    }
                                )
                            ) {
                                ForEach(categorias, id: \.self) { categoria in
                                    Text(categoria)
                                        .tag(categoria)
                                }
                            }
                            .disabled(
                                viewModel.relatorioTemporario?
                                    .lancamentos.first(where: { $0.id == item.id })?
                                    .tipo == "estorno"
                            )
                        }
                        .padding()
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }

                    Button {
                        viewModel.visualizarRelatorio()
                    } label: {
                        Text("Visualizar relatório")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func formatarReais(_ centavos: Int) -> String {
        (Decimal(centavos) / 100).formatted(
            .currency(code: "BRL")
            .locale(Locale(identifier: "pt_BR"))
        )
    }
}

