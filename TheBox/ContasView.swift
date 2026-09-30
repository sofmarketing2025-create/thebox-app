import SwiftUI
import SwiftData
import Charts

struct ContasView: View {
    @Binding var mes: Int
    @Environment(\.modelContext) private var ctx
    @Query private var contas: [Conta]
    @Query private var transacoes: [Transacao]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @Query(sort: \Categoria.ordem) private var categorias: [Categoria]
    @State private var editando: Conta?
    @State private var criando = false
    @State private var pagando: Conta?
    @State private var calendario = false
    @State private var apagando: Conta?

    var body: some View {
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
        let doMes = fin.contasDoMes(mes)
        let faturas = fin.cartoes().filter { fin.fatura($0, em: mes) > 0 }
        let totalContas = doMes.reduce(0) { $0 + $1.valor }
        let totalFaturas = faturas.reduce(0) { $0 + fin.fatura($1, em: mes) }
        let pagoContas = doMes.filter { $0.pago(em: mes) }.reduce(0) { $0 + $1.valor }
        let pagoFaturas = faturas.filter { $0.faturaPaga(em: mes) }.reduce(0) { $0 + fin.fatura($1, em: mes) }
        let quantidade = doMes.count + faturas.count

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cabecalho(sub: "Planejamento", titulo: "Contas") {
                    BotaoCirculo(icone: "calendar") { calendario = true }
                    SeletorMes(mes: $mes)
                    BotaoCirculo(icone: "plus") { criando = true }
                }

                ResumoCard(mes: mes, total: totalContas + totalFaturas, pago: pagoContas + pagoFaturas)

                if !contas.isEmpty {
                    GraficoMeses(dados: ((mes - 3)...(mes + 3)).map { i in
                        PontoMes(mes: i, valor: fin.contasDoMes(i).reduce(0) { $0 + $1.valor })
                    }, selecionado: mes)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(mes == Mes.indice() ? "Este mês" : Mes.nome(mes))
                        .font(.system(size: 19, weight: .bold))
                    Spacer()
                    Text("\(quantidade) \(quantidade == 1 ? "conta" : "contas")")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                if quantidade == 0 {
                    Vazio(titulo: "Nenhuma conta ainda", texto: "Toque no + no topo da tela para adicionar")
                } else {
                    ForEach(faturas) { c in
                        LinhaFatura(cartao: c, valor: fin.fatura(c, em: mes), mes: mes) {
                            c.alternarFatura(em: mes)
                            try? ctx.save()
                            Notificacoes.reagendar(ctx)
                        }
                    }
                    ForEach(doMes) { conta in
                        LinhaConta(conta: conta, mes: mes, icone: icone(conta.categoria),
                                   carteiraCredito: fin.credito(conta.pagamento(em: mes) ?? "")) {
                            if conta.pago(em: mes) {
                                conta.desmarcar(em: mes)
                                try? ctx.save()
                                Notificacoes.reagendar(ctx)
                            } else {
                                pagando = conta
                            }
                        }
                        .onTapGesture { editando = conta }
                        .deslizarParaApagar { apagando = conta }
                        .contextMenu {
                            Button { editando = conta } label: { Label("Editar", systemImage: "pencil") }
                            if conta.recorrente {
                                Button(role: .destructive) {
                                    Exclusao.contaSoNoMes(conta, mes: mes, ctx: ctx)
                                } label: { Label("Apagar só de \(Mes.nome(mes).lowercased())", systemImage: "calendar.badge.minus") }
                            }
                            Button(role: .destructive) {
                                Exclusao.conta(conta, ctx: ctx)
                            } label: {
                                Label(conta.recorrente ? "Apagar todos os meses" : "Apagar conta", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.fundo)
        .sheet(isPresented: $criando) { FormContaView(conta: nil, mesInicial: mes) }
        .sheet(isPresented: $calendario) { CalendarioView(mes: mes) }
        .confirmationDialog("Apagar \(apagando?.nome ?? "")?",
                            isPresented: Binding(get: { apagando != nil }, set: { if !$0 { apagando = nil } }),
                            titleVisibility: .visible,
                            presenting: apagando) { conta in
            if conta.recorrente {
                Button("Só de \(Mes.nome(mes).lowercased())", role: .destructive) {
                    Exclusao.contaSoNoMes(conta, mes: mes, ctx: ctx)
                    apagando = nil
                }
            }
            Button(conta.recorrente ? "Todos os meses" : "Apagar", role: .destructive) {
                Exclusao.conta(conta, ctx: ctx)
                apagando = nil
            }
        }
        .sheet(item: $editando) { conta in FormContaView(conta: conta, mesInicial: mes) }
        .confirmationDialog("Como você pagou?",
                            isPresented: Binding(get: { pagando != nil }, set: { if !$0 { pagando = nil } }),
                            titleVisibility: .visible,
                            presenting: pagando) { conta in
            ForEach(carteiras) { c in
                Button(c.tipo == .credito ? "\(c.nome) (entra na fatura)" : c.nome) {
                    conta.marcarPago(em: mes, carteira: c.nome)
                    try? ctx.save()
                    Notificacoes.reagendar(ctx)
                    pagando = nil
                }
            }
        }
    }

    private func icone(_ nome: String) -> String {
        categorias.first { $0.nome == nome && $0.tipo == .gasto }?.icone ?? Categoria.iconePadrao(nome)
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
                Text(total.moeda)
                    .font(.system(size: 27, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                Text("total de contas").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Legenda(cor: .green, texto: "\(pago.moeda) pago")
                    Legenda(cor: .orange, texto: "\((total - pago).moeda) restante")
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
                    Text("\(Int((p * 100).rounded()))%").font(.system(size: 19, weight: .bold))
                    Text("pago").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110, height: 110)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart {
                ForEach(dados) { d in
                    BarMark(
                        x: .value("Mês", Mes.curto(d.mes)),
                        y: .value("Total", max(d.valor, maxV * 0.025)),
                        width: 26
                    )
                    .cornerRadius(9)
                    .foregroundStyle(d.mes == selecionado && d.valor > 0 ? Color.primary : Color.cartao2)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(maxV * 1.1))
            .frame(height: 120)

            HStack(spacing: 0) {
                ForEach(dados) { d in
                    let on = d.mes == selecionado
                    VStack(spacing: 4) {
                        Text(d.valor.curto)
                        Text(Mes.curto(d.mes))
                    }
                    .font(.system(size: 12, weight: on ? .bold : .medium))
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cartao()
    }
}

struct BotaoStatus: View {
    let pago: Bool
    let atrasada: Bool
    var acao: () -> Void

    var body: some View {
        let cor: Color = pago ? .green : (atrasada ? .red : .orange)
        Button(action: acao) {
            Text(pago ? "Pago" : (atrasada ? "Atrasada" : "Pendente"))
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

struct LinhaConta: View {
    let conta: Conta
    let mes: Int
    var icone = "tag.fill"
    var carteiraCredito = false
    var alternar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icone)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sobreDestaque)
                .frame(width: 48, height: 48)
                .background(Color.destaque, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(conta.nome).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if let parcela = conta.parcela(em: mes) { Chip(parcela) }
                }
                HStack(spacing: 8) {
                    Chip(conta.tipoNome)
                    Text(textoVencimento)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                Text(conta.valor.moeda).font(.system(size: 14, weight: .bold)).lineLimit(1)
                BotaoStatus(pago: conta.pago(em: mes), atrasada: conta.atrasada(em: mes), acao: alternar)
            }
        }
        .padding(16)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.borda))
        .contentShape(Rectangle())
    }

    private var textoVencimento: String {
        if let c = conta.pagamento(em: mes) {
            return carteiraCredito ? "Na fatura \(c)" : "Pago com \(c)"
        }
        let dia = String(format: "%02d", conta.dia)
        return conta.venceMesSeguinte ? "Vence \(dia)/\(Mes.curto(mes + 1).lowercased())" : "Vence dia \(dia)"
    }
}

struct LinhaFatura: View {
    let cartao: Carteira
    let valor: Double
    let mes: Int
    var alternar: () -> Void

    var body: some View {
        let pago = cartao.faturaPaga(em: mes)
        let atrasada = !pago && Mes.data(mes, dia: cartao.diaVencimento, hora: 23) < .now
        HStack(spacing: 14) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.sobreDestaque)
                .frame(width: 48, height: 48)
                .background(Color.destaque, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Fatura \(cartao.nome)").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Chip("Fatura")
                    Text("Vence dia \(String(format: "%02d", cartao.diaVencimento))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                Text(valor.moeda).font(.system(size: 14, weight: .bold)).lineLimit(1)
                BotaoStatus(pago: pago, atrasada: atrasada, acao: alternar)
            }
        }
        .padding(16)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.borda))
    }
}
