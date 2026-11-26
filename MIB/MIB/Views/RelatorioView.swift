//
//  RelatorioView.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import SwiftUI

struct RelatorioView: View {

    let nome: String
    let lancamentos: [LancamentoTemporario]

    var onConcluir: (() -> Void)? = nil
    var onVoltar: (() -> Void)? = nil

    private var despesas: [LancamentoTemporario] {
        lancamentos.filter {
            $0.tipo != "pagamento" &&
            $0.tipo != "cancelado"
        }
    }

    private var categoriasAgrupadas:
        [String: [LancamentoTemporario]] {

        Dictionary(grouping: despesas) {
            $0.categoria
        }
    }

    private var totalGeral: Int {
        despesas.reduce(0) { resultado, item in
            resultado + valorLiquido(item)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text(nome)
                    .font(.title2.bold())

                Text("Total de gastos")
                    .foregroundStyle(.secondary)

                Text(formatarReais(totalGeral))
                    .font(.largeTitle.bold())

                Divider()

                Text("Gastos por categoria")
                    .font(.title2.bold())

                ForEach(
                    categoriasAgrupadas.keys.sorted(),
                    id: \.self
                ) { categoria in

                    let itens = categoriasAgrupadas[categoria] ?? []

                    let totalCategoria = itens.reduce(0) {
                        $0 + valorLiquido($1)
                    }

                    VStack(alignment: .leading, spacing: 12) {

                        HStack {
                            Text(categoria)
                                .font(.headline)

                            Spacer()

                            Text(formatarReais(totalCategoria))
                                .font(.headline)
                        }

                        ForEach(itens) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.descricao)

                                    Text(item.data)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Text(item.nomeArquivoOrigem)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(formatarReais(item.valorCentavos))
                            }
                        }
                    }

                    Divider()
                }

                if let onVoltar {
                    Button("Voltar para revisão") {
                        onVoltar()
                    }
                    .buttonStyle(.bordered)
                }

                if let onConcluir {
                    Button {
                        onConcluir()
                    } label: {
                        Text("Concluir")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Relatório")
    }

    private func valorLiquido(
        _ item: LancamentoTemporario
    ) -> Int {

        switch item.tipo {

        case "compra", "encargo":
            return item.valorCentavos

        case "estorno":
            return -item.valorCentavos

        case "pagamento", "cancelado":
            return 0

        default:
            return 0
        }
    }

    private func formatarReais(_ centavos: Int) -> String {
        (Decimal(centavos) / 100).formatted(
            .currency(code: "BRL")
            .locale(Locale(identifier: "pt_BR"))
        )
    }
}
