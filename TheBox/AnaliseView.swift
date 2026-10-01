import SwiftUI
import SwiftData
import Charts

struct AnaliseView: View {
    @Binding var mes: Int
    @Environment(AppState.self) private var estado
    @Environment(\.modelContext) private var ctx
    @Query private var transacoes: [Transacao]
    @Query private var contas: [Conta]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @Query private var limites: [LimiteMensal]
    @State private var editarLimite = false
    @State private var categoriaEditando: Categoria?
    @State private var insights = false

    var body: some View {
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras, limites: limites)
        let porCategoria = fin.gastoPorCategoria(em: mes)
        let gasto = porCategoria.values.reduce(0, +)
        let limite = fin.limite(em: mes)
        let anterior = fin.gastoTotal(em: mes - 1)
        let temAnterior = fin.temDados(em: mes - 1)
        let cats = categorias.filter { $0.tipo == .gasto }
        let comGasto = cats.filter { (porCategoria[$0.nome] ?? 0) > 0 }
            .sorted { (porCategoria[$0.nome] ?? 0) > (porCategoria[$1.nome] ?? 0) }
        let semGasto = cats.filter { (porCategoria[$0.nome] ?? 0) == 0 }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Cabecalho(sub: "Metas", titulo: "Análise") {
                    BotaoCirculo(icone: "target") { insights = true }
                    SeletorMes(mes: $mes)
                }

                HStack(spacing: 10) {
                    Button { estado.abrirRevisao = true } label: {
                        Label("Revisão da semana", systemImage: "calendar.badge.clock")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(Color.cartao, in: Capsule())
                            .overlay(Capsule().stroke(Color.borda))
                    }
                    Button { estado.abrirFechamento = mes < Mes.indice() ? mes : Mes.indice() - 1 } label: {
                        Label("Fechamento do mês", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(Color.cartao, in: Capsule())
                            .overlay(Capsule().stroke(Color.borda))
                    }
                }
                .buttonStyle(.plain)

                CartaoOrcamento(mes: mes, gasto: gasto, limite: limite) { editarLimite = true }

                CartaoComparacao(mes: mes, atual: gasto, anterior: anterior, temAnterior: temAnterior)

                CartaoTendencias(mes: mes)

                CartaoAssinaturas()

                ForEach(comGasto) { c in
                    LinhaMeta(categoria: c, gasto: porCategoria[c.nome] ?? 0)
                        .cartao(20)
                        .onTapGesture { categoriaEditando = c }
                }

                if !semGasto.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(semGasto) { c in
                            LinhaMeta(categoria: c, gasto: 0)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                                .onTapGesture { categoriaEditando = c }
                            if c.chave != semGasto.last?.chave { Divider().overlay(Color.borda) }
                        }
                    }
                    .cartao(20)
                }

                Historico(dados: ((mes - 5)...mes).map { PontoMes(mes: $0, valor: fin.gastoTotal(em: $0)) }, mes: mes)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.fundo)
        .sheet(isPresented: $editarLimite) {
            EditarValorSheet(titulo: "Limite de \(Mes.nome(mes).lowercased())",
                             subtitulo: "Vale a partir deste mês, meses anteriores não mudam",
                             valor: limite) { novo in
                if let existente = limites.first(where: { $0.mes == mes }) {
                    existente.valor = novo
                } else {
                    ctx.insert(LimiteMensal(mes: mes, valor: novo))
                }
                try? ctx.save()
            }
        }
        .sheet(item: $categoriaEditando) { c in
            EditarValorSheet(titulo: "Limite de \(c.nome)",
                             subtitulo: "Quanto você quer gastar por mês com essa categoria",
                             valor: c.limite) { novo in
                c.limite = novo
                try? ctx.save()
            }
        }
        .fullScreenCover(isPresented: $insights) { InsightsView() }
    }
}

struct CartaoOrcamento: View {
    let mes: Int
    let gasto: Double
    let limite: Double
    var editar: () -> Void

    var body: some View {
        let p = limite > 0 ? gasto / limite : 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("GASTO")
                Spacer()
                Text("DO ORÇAMENTO")
            }
            .font(.system(size: 13, weight: .semibold)).tracking(1.5)
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(gasto.moeda).font(.system(size: 27, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Text(limite > 0 ? porcento(p) : "—").font(.system(size: 27, weight: .heavy))
            }
            BarraProgresso(p: p, cor: limite > 0 ? corPorcentagem(p) : .primary, altura: 5)
                .padding(.vertical, 10)
            Button(action: editar) {
                Text(limite > 0
                     ? "\(gasto.moeda) de \(limite.moedaInteira) em \(Mes.nome(mes).lowercased()) · editar"
                     : "Defina um limite para \(Mes.nome(mes).lowercased()) · editar")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.plain)
        }
        .cartao(26)
    }
}

struct CartaoComparacao: View {
    let mes: Int
    let atual: Double
    let anterior: Double
    let temAnterior: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPARAÇÃO MENSAL")
                .font(.system(size: 14, weight: .semibold)).tracking(1.5)
                .foregroundStyle(.secondary)
            if temAnterior && anterior > 0 {
                let d = (atual - anterior) / anterior
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: d <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .foregroundStyle(d <= 0 ? Color.green : Color.orange)
                    Text("\(porcento(abs(d))) \(d <= 0 ? "a menos" : "a mais")")
                        .font(.system(size: 19, weight: .bold))
                    Text("que \(Mes.nome(mes - 1).lowercased())").foregroundStyle(.secondary)
                }
                Text("\(anterior.moeda) em \(Mes.nome(mes - 1).lowercased()) · \(atual.moeda) em \(Mes.nome(mes).lowercased())")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Disponível a partir do mês que vem, quando \(Mes.nome(mes).lowercased()) virar a base de comparação.")
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .cartao(24)
    }
}

struct LinhaMeta: View {
    let categoria: Categoria
    let gasto: Double

    var body: some View {
        let p = categoria.limite > 0 ? gasto / categoria.limite : 0
        let ativo = gasto > 0
        HStack(spacing: 16) {
            AnelProgresso(p: p, tamanho: 60, linha: 4, cor: corPorcentagem(p))
            Text(categoria.nome).font(.system(size: 15, weight: .medium)).lineLimit(1)
            Spacer(minLength: 6)
            HStack(spacing: 0) {
                if ativo { Text(gasto.moeda).fontWeight(.semibold) }
                Text(categoria.limite > 0 ? " / \(categoria.limite.moedaInteira)" : " / sem limite")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 14))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .opacity(ativo ? 1 : 0.45)
    }
}

struct Historico: View {
    let dados: [PontoMes]
    let mes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gastos nos últimos 6 meses")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Chart(dados) { p in
                BarMark(x: .value("Mês", Mes.curto(p.mes)), y: .value("Total", p.valor), width: 22)
                    .cornerRadius(7)
                    .foregroundStyle(p.mes == mes ? Color.primary : Color.cartao2)
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
        }
        .cartao()
    }
}
