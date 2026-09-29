import SwiftUI
import SwiftData
import Charts

// MARK: - Cálculo

/// Uma conta parcelada que ainda tem parcelas a pagar
struct Divida: Identifiable {
    let conta: Conta
    let restantes: Int
    let fim: Int
    var valor: Double { conta.valor }
    var total: Double { valor * Double(restantes) }
    var id: UUID { conta.chave }
}

enum MetodoQuitacao: String, CaseIterable, Identifiable {
    case bolaDeNeve, avalanche
    var id: String { rawValue }
    var nome: String { self == .bolaDeNeve ? "Bola de neve" : "Avalanche" }
    var explicacao: String {
        self == .bolaDeNeve
            ? "Quita primeiro as dívidas menores. Cada uma que acaba libera dinheiro pra próxima, e você vê resultado rápido."
            : "Quita primeiro as dívidas com juros mais altos. Economiza mais dinheiro no total."
    }
}

enum PlanoCalculo {
    static func ultimoMes(_ c: Conta) -> Int {
        c.inicio + c.totalParcelas - c.adiantadas - max(c.parcelaAtual, 1)
    }

    static func dividas(_ contas: [Conta], hoje: Int) -> [Divida] {
        contas.filter(\.parcelada).compactMap { c in
            let ultimo = ultimoMes(c)
            guard ultimo >= c.inicio else { return nil }
            let pendentes = (c.inicio...ultimo).filter { c.ocorre(em: $0) && !c.pago(em: $0) }.count
            guard pendentes > 0 else { return nil }
            return Divida(conta: c, restantes: pendentes, fim: max(ultimo, hoje))
        }
    }

    static func ordenar(_ d: [Divida], _ metodo: MetodoQuitacao) -> [Divida] {
        switch metodo {
        case .bolaDeNeve:
            return d.sorted { ($0.total, $0.fim) < ($1.total, $1.fim) }
        case .avalanche:
            return d.sorted { $0.conta.juros != $1.conta.juros ? $0.conta.juros > $1.conta.juros : $0.total < $1.total }
        }
    }

    /// Simula o plano mês a mês: paga a parcela normal de cada dívida e usa o valor extra
    /// (mais o que as dívidas quitadas liberam) pra adiantar parcelas na ordem escolhida.
    static func simular(_ ordem: [Divida], extra: Double, hoje: Int) -> (fim: Int, fimPorConta: [UUID: Int]) {
        var resta: [UUID: Int] = [:]
        for d in ordem { resta[d.id] = d.restantes }
        var fimPor: [UUID: Int] = [:]
        var caixa = 0.0
        var m = hoje
        while resta.values.contains(where: { $0 > 0 }) && m < hoje + 600 {
            // o que as dívidas já quitadas deixam de cobrar vira reforço
            let liberado = ordem.filter { (fimPor[$0.id] ?? Int.max) < m }.reduce(0) { $0 + $1.valor }
            for d in ordem where (resta[d.id] ?? 0) > 0 {
                resta[d.id, default: 0] -= 1
                if resta[d.id] == 0 { fimPor[d.id] = m }
            }
            caixa += max(extra, 0) + liberado
            for d in ordem where (resta[d.id] ?? 0) > 0 {
                while caixa >= d.valor && (resta[d.id] ?? 0) > 0 {
                    caixa -= d.valor
                    resta[d.id, default: 0] -= 1
                }
                if resta[d.id] == 0 { fimPor[d.id] = m }
                if caixa < d.valor { break }
            }
            m += 1
        }
        return (fimPor.values.max() ?? hoje, fimPor)
    }

    /// Paga uma parcela a mais agora (sai do fim do parcelamento), com opção de desfazer
    @MainActor
    static func adiantar(_ c: Conta, ctx: ModelContext) {
        let t = Transacao(tipo: .gasto, valor: c.valor, categoria: c.categoria.isEmpty ? "Outros" : c.categoria,
                          carteira: "", descricao: "Adiantamento: \(c.nome)")
        withAnimation {
            ctx.insert(t)
            c.adiantadas += 1
            try? ctx.save()
        }
        Notificacoes.reagendar(ctx)
        AppState.shared.oferecerDesfazer("Parcela de \(c.nome) adiantada") {
            c.adiantadas = max(0, c.adiantadas - 1)
            ctx.delete(t)
            try? ctx.save()
            Notificacoes.reagendar(ctx)
        }
    }
}

func mesAno(_ i: Int) -> String {
    "\(Mes.curto(i).lowercased())/\(String(format: "%02d", Mes.ano(i) % 100))"
}

// MARK: - Tela

struct PlanoQuitacaoView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var contas: [Conta]
    @Query private var transacoes: [Transacao]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @AppStorage("renda") private var rendaManual: Double = 0
    @AppStorage("metodoQuitacao") private var metodoRaw = MetodoQuitacao.bolaDeNeve.rawValue
    @AppStorage("extraQuitacao") private var extra: Double = -1
    @State private var editarRenda = false
    @State private var adiantando: Conta?
    @State private var editando: Conta?

    private var metodo: MetodoQuitacao { MetodoQuitacao(rawValue: metodoRaw) ?? .bolaDeNeve }

    var body: some View {
        let hoje = Mes.indice()
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
        let dividas = PlanoCalculo.dividas(contas, hoje: hoje)
        let ordem = PlanoCalculo.ordenar(dividas, metodo)
        let totalDevido = dividas.reduce(0) { $0 + $1.total }
        let fimNatural = dividas.map(\.fim).max() ?? hoje
        let compromissoHoje = fin.contasDoMes(hoje).reduce(0) { $0 + $1.valor }
        let registrada = max(fin.receitas(em: hoje), fin.receitas(em: hoje + 1))
        let renda = rendaManual > 0 ? rendaManual : registrada
        let mediaGastos = mediaGastosAvulsos(fin, hoje: hoje)
        let sobra = renda - compromissoHoje - mediaGastos
        let extraAtual = extra >= 0 ? extra : max(0, (sobra / 50).rounded(.down) * 50)
        let simulado = PlanoCalculo.simular(ordem, extra: extraAtual, hoje: hoje)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Cabecalho(sub: "Plano de quitação", titulo: "Quitar")

                if dividas.isEmpty {
                    Vazio(icone: "checkmark.seal", titulo: "Nenhuma parcela pendente",
                          texto: "Cadastre suas contas parceladas na aba Contas (parcela atual e nº de parcelas) pra montar o plano.")
                        .cartao(18)
                } else {
                    resumo(total: totalDevido, parcelas: dividas.reduce(0) { $0 + $1.restantes }, fim: fimNatural)
                }
                cartaoSobra(renda: renda, registrada: rendaManual == 0 && registrada > 0,
                            compromisso: compromissoHoje, media: mediaGastos, sobra: sobra)
                if !dividas.isEmpty {
                    linhaDoTempo(fin: fin, hoje: hoje, fim: max(fimNatural, hoje + 1))
                    simulador(extra: extraAtual, fimNatural: fimNatural, fimPlano: simulado.fim, hoje: hoje)
                    ordemQuitacao(ordem, fimPlano: simulado.fimPorConta, hoje: hoje)
                }
                let fixas = contas.filter { !$0.parcelada && $0.ocorre(em: hoje) }.sorted { $0.valor > $1.valor }
                if !fixas.isEmpty {
                    cobrancasFixas(fixas, hoje: hoje)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.fundo)
        .sheet(item: $editando) { c in FormContaView(conta: c, mesInicial: Mes.indice()) }
        .sheet(isPresented: $editarRenda) {
            EditarValorSheet(titulo: "Sua renda por mês",
                             subtitulo: "Quanto entra por mês, somando salário e outras receitas fixas",
                             valor: renda) { rendaManual = $0 }
        }
        .confirmationDialog("Adiantar uma parcela de \(adiantando?.nome ?? "")?",
                            isPresented: Binding(get: { adiantando != nil }, set: { if !$0 { adiantando = nil } }),
                            titleVisibility: .visible) {
            Button("Adiantar \(adiantando?.valor.moeda ?? "")") {
                if let adiantando { PlanoCalculo.adiantar(adiantando, ctx: ctx) }
                adiantando = nil
            }
        } message: {
            Text("Registra um gasto com esse valor hoje e tira a última parcela do parcelamento.")
        }
    }

    private func mediaGastosAvulsos(_ fin: Financas, hoje: Int) -> Double {
        let anteriores = ((hoje - 3)...(hoje - 1)).map { fin.gastosAvulsos(em: $0) }.filter { $0 > 0 }
        if !anteriores.isEmpty { return anteriores.reduce(0, +) / Double(anteriores.count) }
        return fin.gastosAvulsos(em: hoje)
    }

    // MARK: Partes

    private func resumo(total: Double, parcelas: Int, fim: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VOCÊ AINDA DEVE").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
            Text(total.moeda).font(.system(size: 32, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(parcelas) parcelas · livre em \(Mes.nome(fim).lowercased()) de \(String(Mes.ano(fim)))")
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .cartao(20)
    }

    private func cartaoSobra(renda: Double, registrada: Bool, compromisso: Double, media: Double, sobra: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("QUANTO SOBRA POR MÊS").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text(renda > 0 ? sobra.moeda : "—")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(renda == 0 ? Color.secondary : (sobra >= 0 ? Color.green : Color.red))
            }
            .padding(.bottom, 6)
            Button { editarRenda = true } label: {
                HStack {
                    Text(renda > 0 ? "Renda" : "Informe sua renda")
                    Spacer()
                    Text(renda > 0 ? renda.moeda : "tocar aqui").fontWeight(.semibold)
                    Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .font(.system(size: 15))
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divisor()
            LinhaStat(titulo: "Contas deste mês", valor: "-" + compromisso.moeda)
            Divisor()
            LinhaStat(titulo: "Média dos gastos do dia a dia", valor: "-" + media.moeda)
            if registrada {
                Text("Renda = receitas registradas neste mês ou no próximo. Toque pra ajustar.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
            }
            if renda > 0 && sobra < 0 {
                Text("As contas e gastos passam da renda. Olhe a Análise pra ver onde cortar antes de adiantar parcelas.")
                    .font(.system(size: 12)).foregroundStyle(.red).padding(.top, 6)
            }
        }
        .cartao(20)
    }

    private func linhaDoTempo(fin: Financas, hoje: Int, fim: Int) -> some View {
        let meses = Array(hoje...min(fim + 1, hoje + 35))
        let pontos = meses.map { PontoMes(mes: $0, valor: fin.contasDoMes($0).reduce(0) { $0 + $1.valor }) }
        let valor: (Int) -> Double = { i in fin.contasDoMes(hoje + i).reduce(0) { $0 + $1.valor } }
        return VStack(alignment: .leading, spacing: 12) {
            Text("CONTAS POR MÊS ATÉ FICAR LIVRE").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
            Chart(pontos) { p in
                BarMark(x: .value("Mês", mesAno(p.mes)), y: .value("Total", p.valor))
                    .cornerRadius(5)
                    .foregroundStyle(p.mes == hoje ? Color.primary : Color.cartao2)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 9)) }
            }
            .frame(height: 130)
            HStack(spacing: 0) {
                marco("Agora", valor(0))
                marco("Em 3 meses", valor(3))
                marco("Em 6 meses", valor(6))
                marco("Em 12 meses", valor(12))
            }
        }
        .cartao(20)
    }

    private func marco(_ titulo: String, _ v: Double) -> some View {
        VStack(spacing: 3) {
            Text(titulo).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(v.moedaInteira).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func simulador(extra: Double, fimNatural: Int, fimPlano: Int, hoje: Int) -> some View {
        let ganho = fimNatural - fimPlano
        return VStack(alignment: .leading, spacing: 12) {
            Text("SIMULADOR").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
            HStack {
                Text("Adiantar por mês").font(.system(size: 15))
                Spacer()
                Button { self.extra = max(0, extra - 50) } label: { Image(systemName: "minus") }
                    .frame(width: 34, height: 34).background(Color.cartao2, in: Circle())
                Text(extra.moedaInteira).font(.system(size: 17, weight: .bold)).frame(minWidth: 90)
                Button { self.extra = extra + 50 } label: { Image(systemName: "plus") }
                    .frame(width: 34, height: 34).background(Color.cartao2, in: Circle())
            }
            .buttonStyle(.plain)
            Picker("Método", selection: $metodoRaw) {
                ForEach(MetodoQuitacao.allCases) { m in Text(m.nome).tag(m.rawValue) }
            }
            .pickerStyle(.segmented)
            Text(metodo.explicacao).font(.system(size: 12)).foregroundStyle(.secondary)
            if metodo == .avalanche && !contas.contains(where: { $0.juros > 0 }) {
                Text("Pra avalanche funcionar, coloque os juros ao mês em cada conta (Editar conta).")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                if ganho > 0 {
                    Text("Livre em \(mesAno(fimPlano)) em vez de \(mesAno(fimNatural))")
                        .font(.system(size: 18, weight: .bold))
                    Text("\(ganho) \(ganho == 1 ? "mês" : "meses") antes, adiantando \(extra.moedaInteira) por mês e usando o que cada dívida quitada libera.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Text("Livre em \(mesAno(fimNatural))").font(.system(size: 18, weight: .bold))
                    Text("Aumente o valor pra adiantar e veja quantos meses você ganha.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cartao2.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .cartao(20)
    }

    /// Botão "•••" com Editar / Remover só deste mês / Remover todos os meses
    private func menuConta(_ c: Conta, hoje: Int) -> some View {
        Menu {
            Button { editando = c } label: { Label("Editar", systemImage: "pencil") }
            if c.recorrente {
                Button(role: .destructive) {
                    Exclusao.contaSoNoMes(c, mes: hoje, ctx: ctx)
                } label: { Label("Remover só de \(Mes.nome(hoje).lowercased())", systemImage: "calendar.badge.minus") }
            }
            Button(role: .destructive) {
                Exclusao.conta(c, ctx: ctx)
            } label: { Label(c.recorrente ? "Remover todos os meses" : "Remover", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.cartao2, in: Circle())
        }
    }

    private func cobrancasFixas(_ lista: [Conta], hoje: Int) -> some View {
        let total = lista.reduce(0) { $0 + $1.valor }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COBRANÇAS FIXAS DESTE MÊS").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Text("\(total.moeda) no total. Cada uma que você cortar vira dinheiro pra quitar mais rápido.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.leading, 6)
            VStack(spacing: 0) {
                ForEach(lista) { c in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.nome).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text("\(c.tipoNome) · vence dia \(c.dia)\(c.pago(em: hoje) ? " · pago" : "")")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(c.valor.moeda).font(.system(size: 15, weight: .bold))
                        menuConta(c, hoje: hoje)
                    }
                    .padding(.vertical, 10)
                    if c.chave != lista.last?.chave { Divisor() }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.borda))
        }
    }

    private func ordemQuitacao(_ ordem: [Divida], fimPlano: [UUID: Int], hoje: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ORDEM DE QUITAÇÃO").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                .padding(.leading, 6)
            ForEach(Array(ordem.enumerated()), id: \.element.id) { i, d in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.sobreDestaque)
                        .frame(width: 26, height: 26)
                        .background(Color.destaque, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(d.conta.nome).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(d.total.moeda).font(.system(size: 15, weight: .bold))
                            menuConta(d.conta, hoje: hoje)
                        }
                        Text("\(d.restantes)x de \(d.valor.moeda)\(d.conta.juros > 0 ? " · \(d.conta.juros.formatted(.number.precision(.fractionLength(0...2)).locale(ptBR)))% a.m." : "")")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text("Termina \(mesAno(d.fim))").foregroundStyle(.secondary)
                            if let f = fimPlano[d.id], f < d.fim {
                                Text("→ \(mesAno(f)) com o plano").foregroundStyle(.green)
                            }
                        }
                        .font(.system(size: 12))
                        Button { adiantando = d.conta } label: {
                            Label("Adiantar parcela", systemImage: "forward.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Color.cartao2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .cartao(16)
            }
        }
    }
}
