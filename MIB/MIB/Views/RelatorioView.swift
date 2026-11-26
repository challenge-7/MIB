//
//  RelatorioView.swift
//  MIB
//
//  Created by Gabriel Groppo on 25/11/26.
//

import SwiftUI
import SwiftData

struct RelatorioView: View {

    let fatura: FaturaSalva

    private var despesas: [Lancamento] {
        fatura.lancamentos.filter {
            $0.tipo != "pagamento"
        }
    }

    private var categoriasAgrupadas: [String: [Lancamento]] {
        Dictionary(grouping: despesas) {
            $0.categoria
        }
    }

    private var totalGeral: Int {
        despesas.reduce(0) { total, lancamento in
            total + valorLiquido(lancamento)
        }
    }


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Resumo geral

                VStack(alignment: .leading, spacing: 8) {

                    Text("Total de gastos")
                        .foregroundStyle(.secondary)

                    Text(formatarReais(totalGeral))
                        .font(.largeTitle.bold())

                    Text(fatura.nomeArquivo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Gastos por categoria

                Text("Gastos por categoria")
                    .font(.title2.bold())

                if despesas.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma despesa encontrada",
                        systemImage: "tray",
                        description: Text(
                            "Não foram identificadas despesas nesta fatura."
                        )
                    )
                }

                ForEach(
                    categoriasAgrupadas.keys.sorted(),
                    id: \.self
                ) { categoria in

                    let itens = categoriasAgrupadas[categoria] ?? []

                    let totalCategoria = itens.reduce(0) {
                        total, lancamento in

                        total + valorLiquido(lancamento)
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {

                        HStack {
                            Text(categoria)
                                .font(.headline)

                            Spacer()

                            Text(formatarReais(totalCategoria))
                                .font(.headline)
                        }

                        ForEach(itens) { lancamento in

                            HStack(alignment: .top) {

                                VStack(
                                    alignment: .leading,
                                    spacing: 4
                                ) {

                                    Text(lancamento.descricao)
                                        .font(.subheadline)

                                    Text(lancamento.data)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(
                                    formatarReais(
                                        lancamento.valorCentavos
                                    )
                                )
                                .font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle("Relatório")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func valorLiquido(
        _ lancamento: Lancamento
    ) -> Int {

        switch lancamento.tipo {

        case "compra", "encargo":
            return lancamento.valorCentavos

        case "estorno":
            return -lancamento.valorCentavos

        case "pagamento":
            return 0

        default:
            return 0
        }
    }

    private func formatarReais(_ centavos: Int) -> String {

        let valor = Decimal(centavos) / 100

        return valor.formatted(
            .currency(code: "BRL")
            .locale(Locale(identifier: "pt_BR"))
        )
    }
}
