import SwiftUI
import SwiftData
import Charts

struct FatiaCategoria: Identifiable {
    let categoria: Categoria
    let valor: Double
    var id: String { categoria.rawValue }
}

struct AnaliseView: View {
    @Query private var gastos: [Gasto]
    @Query private var contas: [Conta]
    @State private var mes = Mes.indice()

    private func gastosTotal(em i: Int) -> Double {
        gastos.filter { $0.mes == i }.reduce(0) { $0 + $1.valor }
    }

    var body: some View {
        let doMes = gastos.filter { $0.mes == mes }
        let total = doMes.reduce(0) { $0 + $1.valor }
        let contasTotal = contas.filter { $0.ocorre(em: mes) }.reduce(0) { $0 + $1.valor }
        let fatias = Categoria.allCases
            .map { c in FatiaCategoria(categoria: c, valor: doMes.filter { $0.categoria == c }.reduce(0) { $0 + $1.valor }) }
            .filter { $0.valor > 0 }
            .sorted { $0.valor > $1.valor }
        let historico = ((mes - 5)...mes).map { PontoMes(mes: $0, valor: gastosTotal(em: $0)) }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cabecalho(sub: "Resumo do mês", titulo: "Análise") {
                    SeletorMes(mes: $mes)
                }

                VStack(spacing: 0) {
                    LinhaStat(titulo: "Gastos", valor: total.brl)
                    Divider().overlay(Color.borda)
                    LinhaStat(titulo: "Contas", valor: contasTotal.brl)
                    Divider().overlay(Color.borda)
                    LinhaStat(titulo: "Total do mês", valor: (total + contasTotal).brl, destaque: true)
                }
                .cartao()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Gastos por categoria")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if fatias.isEmpty {
                        Text("Nenhum gasto em \(Mes.nome(mes).lowercased()).").foregroundStyle(.secondary)
                    } else {
                        Chart(fatias) { f in
                            SectorMark(angle: .value("Valor", f.valor), innerRadius: .ratio(0.62), angularInset: 2)
                                .cornerRadius(4)
                                .foregroundStyle(f.categoria.cor)
                        }
                        .frame(height: 180)
                        .padding(.vertical, 6)

                        ForEach(fatias) { f in
                            HStack(spacing: 10) {
                                Image(systemName: f.categoria.icone)
                                    .foregroundStyle(f.categoria.cor)
                                    .frame(width: 22)
                                Text(f.categoria.nome)
                                Spacer()
                                Text("\(Int((f.valor / max(total, 0.01) * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                                Text(f.valor.brl).fontWeight(.semibold)
                            }
                            .font(.system(size: 15))
                        }
                    }
                }
                .cartao()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Gastos nos últimos 6 meses")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Chart(historico) { p in
                        BarMark(x: .value("Mês", Mes.curto(p.mes)), y: .value("Total", p.valor), width: 22)
                            .cornerRadius(7)
                            .foregroundStyle(p.mes == mes ? Color.white : Color.cartao2)
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 150)
                }
                .cartao()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.fundo)
    }
}
