import SwiftUI
import SwiftData
import Charts

struct ContasView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var contas: [Conta]
    @State private var mes = Mes.indice()
    @State private var editando: Conta?
    @State private var criando = false

    private func lista(em i: Int) -> [Conta] {
        contas.filter { $0.ocorre(em: i) }.sorted { $0.dia < $1.dia }
    }
    private func total(em i: Int) -> Double {
        lista(em: i).reduce(0) { $0 + $1.valor }
    }
    private func compromissos(em i: Int) -> [Conta] {
        contas.filter { $0.tipo != .unico && $0.ocorre(em: i) }
    }

    var body: some View {
        let doMes = lista(em: mes)
        let tot = doMes.reduce(0) { $0 + $1.valor }
        let pago = doMes.filter { $0.pago(em: mes) }.reduce(0) { $0 + $1.valor }
        let ativos = compromissos(em: mes)
        let grafico = ((mes - 3)...(mes + 3)).map { PontoMes(mes: $0, valor: total(em: $0)) }
        let serie = (mes...(mes + 5)).map { i in
            PontoMes(mes: i, valor: compromissos(em: i).reduce(0) { $0 + $1.valor })
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cabecalho(sub: "Planejamento", titulo: "Contas") {
                    SeletorMes(mes: $mes)
                    BotaoMais { criando = true }
                }

                ResumoCard(mes: mes, total: tot, pago: pago)
                GraficoMeses(dados: grafico, selecionado: mes)
                CompromissosCard(total: ativos.reduce(0) { $0 + $1.valor }, quantidade: ativos.count, serie: serie)

                HStack(alignment: .firstTextBaseline) {
                    Text(mes == Mes.indice() ? "Este mês" : Mes.nome(mes))
                        .font(.system(size: 24, weight: .bold))
                    Spacer()
                    Text("\(doMes.count) \(doMes.count == 1 ? "conta" : "contas")")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                if doMes.isEmpty {
                    Vazio(texto: "Nenhuma conta em \(Mes.nome(mes).lowercased()).",
                          botao: "Adicionar conta") { criando = true }
                } else {
                    ForEach(doMes) { conta in
                        LinhaConta(conta: conta, mes: mes) {
                            conta.alternarPago(em: mes)
                            try? ctx.save()
                            Notificacoes.reagendar(ctx)
                        }
                        .onTapGesture { editando = conta }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.fundo)
        .sheet(isPresented: $criando) { FormConta(conta: nil, mesInicial: mes) }
        .sheet(item: $editando) { conta in FormConta(conta: conta, mesInicial: mes) }
    }
}

struct ResumoCard: View {
    let mes: Int
    let total: Double
    let pago: Double

    var body: some View {
        let p = total > 0 ? pago / total : 0
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Mes.nome(mes).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(.secondary)
                Text(total.brl)
                    .font(.system(size: 36, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                Text("total de contas").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Legenda(cor: .green, texto: "\(pago.brl) pago")
                    Legenda(cor: .orange, texto: "\((total - pago).brl) restante")
                }
                .padding(.top, 14)
            }
            Spacer(minLength: 8)
            ZStack {
                Circle().stroke(Color.cartao2, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: p)
                VStack(spacing: 0) {
                    Text("\(Int((p * 100).rounded()))%").font(.system(size: 24, weight: .bold))
                    Text("pago").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
        }
        .cartao()
    }
}

struct GraficoMeses: View {
    let dados: [PontoMes]
    let selecionado: Int

    var body: some View {
        let maxV = max(dados.map(\.valor).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
            Text("Total de contas por mês")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart {
                ForEach(dados) { d in
                    BarMark(
                        x: .value("Mês", Mes.curto(d.mes)),
                        y: .value("Total", max(d.valor, maxV * 0.025)),
                        width: 26
                    )
                    .cornerRadius(9)
                    .foregroundStyle(d.mes == selecionado && d.valor > 0 ? Color.white : Color.cartao2)
                }
                ForEach(dados) { d in
                    LineMark(
                        x: .value("Mês", Mes.curto(d.mes)),
                        y: .value("Linha", d.valor + maxV * 0.12)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.white)
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
                    .symbol {
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(maxV * 1.2))
            .frame(height: 150)

            HStack(spacing: 0) {
                ForEach(dados) { d in
                    let on = d.mes == selecionado
                    VStack(spacing: 4) {
                        Text(on && d.valor > 0 ? "R$\(d.valor.curto)" : d.valor.curto)
                        Text(Mes.curto(d.mes))
                    }
                    .font(.system(size: 12, weight: on ? .bold : .medium))
                    .foregroundStyle(on ? Color.white : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cartao()
    }
}

struct CompromissosCard: View {
    let total: Double
    let quantidade: Int
    let serie: [PontoMes]

    var body: some View {
        let maxV = max(serie.map(\.valor).max() ?? 0, 1)
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Compromissos ativos").font(.system(size: 19, weight: .semibold))
                Text(total.brl).font(.system(size: 22, weight: .bold))
                Text("\(quantidade) \(quantidade == 1 ? "ativo" : "ativos") por mês")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Chart {
                ForEach(serie) { p in
                    AreaMark(x: .value("Mês", p.mes), y: .value("Total", p.valor))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [.white.opacity(0.18), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Mês", p.mes), y: .value("Total", p.valor))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.white)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(maxV * 1.15))
            .frame(width: 130, height: 60)
        }
        .cartao()
    }
}

struct LinhaConta: View {
    let conta: Conta
    let mes: Int
    var alternar: () -> Void

    var body: some View {
        let pago = conta.pago(em: mes)
        let atrasada = conta.atrasada(em: mes)
        let cor: Color = pago ? .green : (atrasada ? .red : .orange)
        let status = pago ? "Pago" : (atrasada ? "Atrasada" : "Pendente")

        HStack(spacing: 14) {
            Text(String(conta.nome.prefix(1)).uppercased())
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(conta.nome).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    if let parcela = conta.parcela(em: mes) { Chip(parcela) }
                }
                HStack(spacing: 8) {
                    Chip(conta.tipo.nome)
                    Text("Vence dia \(String(format: "%02d", conta.dia))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if conta.tipo == .fixo {
                        Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                Text(conta.valor.brl).font(.system(size: 17, weight: .bold)).lineLimit(1)
                Button(action: alternar) {
                    Text(status)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(cor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(cor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(cor.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.borda))
        .contentShape(Rectangle())
    }
}
