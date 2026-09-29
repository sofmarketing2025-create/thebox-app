import SwiftUI
import SwiftData
import Charts

// MARK: - Cálculo

/// Uma parcela ainda não paga de uma conta que tem fim
struct Parcela {
    let mes: Int
    let valor: Double
    let conta: Conta
}

/// Uma dívida = todas as contas com fim que têm o mesmo nome (ex.: várias "Nubank")
struct Divida: Identifiable {
    let nome: String
    let parcelas: [Parcela]
    var id: String { PlanoCalculo.chave(nome) }
    var restantes: Int { parcelas.count }
    var total: Double { parcelas.reduce(0) { $0 + $1.valor } }
    var fim: Int { parcelas.last?.mes ?? 0 }
    var juros: Double { parcelas.map(\.conta.juros).max() ?? 0 }
    var proxima: Parcela? { parcelas.first }
    var ultima: Parcela? { parcelas.last }
    var contas: [Conta] {
        var vistas = Set<UUID>()
        return parcelas.map(\.conta).filter { vistas.insert($0.chave).inserted }
    }
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
    static func chave(_ nome: String) -> String {
        nome.lowercased().folding(options: .diacriticInsensitive, locale: ptBR).trimmingCharacters(in: .whitespaces)
    }

    static func ultimoMes(_ c: Conta) -> Int {
        c.parcelada ? c.inicio + c.totalParcelas - c.adiantadas - max(c.parcelaAtual, 1) : c.inicio
    }

    /// Conta com fim: parcelada ou única (as fixas que repetem pra sempre ficam de fora)
    static func temFim(_ c: Conta) -> Bool { c.parcelada || !c.repetir }

    private struct Grupo {
        var nome: String
        var parcelas: [Parcela]
    }

    static func dividas(_ contas: [Conta], hoje: Int) -> [Divida] {
        var grupos: [String: Grupo] = [:]
        for c in contas where temFim(c) {
            let ultimo = ultimoMes(c)
            guard ultimo >= hoje else { continue }
            for m in max(c.inicio, hoje)...ultimo where c.ocorre(em: m) && !c.pago(em: m) {
                grupos[chave(c.nome), default: Grupo(nome: c.nome, parcelas: [])]
                    .parcelas.append(Parcela(mes: m, valor: c.valor, conta: c))
            }
        }
        return grupos.values
            .filter { !$0.parcelas.isEmpty }
            .map { Divida(nome: $0.nome, parcelas: $0.parcelas.sorted { $0.mes < $1.mes }) }
    }

    static func ordenar(_ d: [Divida], _ metodo: MetodoQuitacao) -> [Divida] {
        switch metodo {
        case .bolaDeNeve:
            return d.sorted { ($0.total, $0.fim) < ($1.total, $1.fim) }
        case .avalanche:
            return d.sorted { $0.juros != $1.juros ? $0.juros > $1.juros : $0.total < $1.total }
        }
    }

    /// Simula mês a mês. Cada mês as parcelas vencem normalmente; o valor extra só é usado
    /// se sobrar dinheiro naquele mês de verdade, e o que as dívidas já quitadas deixam de
    /// cobrar vai pra próxima da fila (bola de neve).
    static func simular(_ ordem: [Divida], extra: Double, hoje: Int,
                        sobraMes: (Int) -> Double) -> (fim: Int, fimPorConta: [String: Int]) {
        var resta: [String: [Parcela]] = [:]
        for d in ordem { resta[d.id] = d.parcelas }
        var fimPor: [String: Int] = [:]
        let fimMax = ordem.map(\.fim).max() ?? hoje
        var caixa = 0.0
        var m = hoje
        while resta.values.contains(where: { !$0.isEmpty }) && m <= fimMax {
            var previsto = 0.0
            var pago = 0.0
            for d in ordem {
                previsto += d.parcelas.filter { $0.mes == m }.reduce(0) { $0 + $1.valor }
                var lista = resta[d.id] ?? []
                pago += lista.filter { $0.mes <= m }.reduce(0) { $0 + $1.valor }
                lista.removeAll { $0.mes <= m }
                resta[d.id] = lista
                if lista.isEmpty && fimPor[d.id] == nil { fimPor[d.id] = m }
            }
            let liberado = max(0, previsto - pago)
            caixa += liberado + min(max(extra, 0), max(0, sobraMes(m)))
            for d in ordem {
                var lista = resta[d.id] ?? []
                while let u = lista.last, caixa >= u.valor {
                    caixa -= u.valor
                    lista.removeLast()
                }
                resta[d.id] = lista
                if lista.isEmpty {
                    if fimPor[d.id] == nil { fimPor[d.id] = m }
                } else {
                    break
                }
            }
            m += 1
        }
        return (fimPor.values.max() ?? hoje, fimPor)
    }

    /// Paga agora a última parcela da dívida (encurta o prazo), com opção de desfazer
    @MainActor
    static func adiantar(_ d: Divida, ctx: ModelContext) {
        guard let p = d.ultima else { return }
        let c = p.conta
        let t = Transacao(tipo: .gasto, valor: p.valor, categoria: c.categoria.isEmpty ? "Outros" : c.categoria,
                          carteira: "", descricao: "Adiantamento: \(c.nome)")
        let parcelada = c.parcelada
        withAnimation {
            ctx.insert(t)
            if parcelada { c.adiantadas += 1 } else { c.excluir(em: p.mes) }
            try? ctx.save()
        }
        Notificacoes.reagendar(ctx)
        AppState.shared.oferecerDesfazer("Parcela de \(c.nome) adiantada") {
            if parcelada { c.adiantadas = max(0, c.adiantadas - 1) } else { c.restaurar(em: p.mes) }
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
    @State private var adiantando: Divida?
    @State private var editando: Conta?

    private var metodo: MetodoQuitacao { MetodoQuitacao(rawValue: metodoRaw) ?? .bolaDeNeve }

    var body: some View {
        let hoje = Mes.indice()
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
        let dividas = PlanoCalculo.dividas(contas, hoje: hoje)
        let ordem = PlanoCalculo.ordenar(dividas, metodo)
        let totalDevido = dividas.reduce(0) { $0 + $1.total }
        let fimNatural = dividas.map(\.fim).max() ?? hoje
        let registrada = (hoje...(hoje + 2)).map { fin.receitas(em: $0) }.max() ?? 0
        let renda = rendaManual > 0 ? rendaManual : registrada
        let mediaGastos = mediaGastosAvulsos(fin, hoje: hoje)
        let contasDe: (Int) -> Double = { m in fin.contasDoMes(m).reduce(0) { $0 + $1.valor } }
        let sobraMes: (Int) -> Double = { m in renda - contasDe(m) - mediaGastos }
        // mês mais apertado entre este e os próximos 3
        let apertado = (hoje...(hoje + 3)).min { sobraMes($0) < sobraMes($1) } ?? hoje
        let sobra = sobraMes(apertado)
        let extraAtual = extra >= 0 ? extra : max(0, (sobra / 50).rounded(.down) * 50)
        let simulado = PlanoCalculo.simular(ordem, extra: extraAtual, hoje: hoje, sobraMes: sobraMes)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Cabecalho(sub: "Plano de quitação", titulo: "Quitar")

                if dividas.isEmpty {
                    Vazio(icone: "checkmark.seal", titulo: "Nenhuma dívida com fim",
                          texto: "Contas parceladas ou únicas deste mês em diante aparecem aqui. As que repetem todo mês ficam em Cobranças fixas.")
                        .cartao(18)
                } else {
                    resumo(total: totalDevido, parcelas: dividas.reduce(0) { $0 + $1.restantes }, fim: fimNatural)
                }
                cartaoSobra(renda: renda, registrada: rendaManual == 0 && registrada > 0,
                            mes: apertado, compromisso: contasDe(apertado), media: mediaGastos, sobra: sobra)
                if !dividas.isEmpty {
                    linhaDoTempo(fin: fin, hoje: hoje, fim: max(fimNatural, hoje + 1))
                    simulador(extra: extraAtual, fimNatural: fimNatural, fimPlano: simulado.fim, hoje: hoje)
                    ordemQuitacao(ordem, fimPlano: simulado.fimPorConta, hoje: hoje)
                }
                let fixas = contas.filter { !PlanoCalculo.temFim($0) && ($0.ocorre(em: hoje) || $0.ocorre(em: hoje + 1)) }
                    .sorted { $0.valor > $1.valor }
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
            Button("Adiantar \(adiantando?.ultima?.valor.moeda ?? "")") {
                if let adiantando { PlanoCalculo.adiantar(adiantando, ctx: ctx) }
                adiantando = nil
            }
        } message: {
            Text("Registra um gasto com esse valor hoje e tira a última parcela, a de \(adiantando?.ultima.map { mesAno($0.mes) } ?? "").")
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

    private func cartaoSobra(renda: Double, registrada: Bool, mes: Int, compromisso: Double, media: Double, sobra: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("QUANTO SOBRA").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                    Text("no mês mais apertado: \(Mes.nome(mes).lowercased())").font(.system(size: 12)).foregroundStyle(.secondary)
                }
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
            LinhaStat(titulo: "Contas de \(Mes.nome(mes).lowercased())", valor: "-" + compromisso.moeda)
            Divisor()
            LinhaStat(titulo: "Média dos gastos do dia a dia", valor: "-" + media.moeda)
            if registrada {
                Text("Renda = maior receita registrada entre este mês e os próximos 2. Toque pra ajustar.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 6)
            }
            if renda > 0 && sobra < 0 {
                Text("Em \(Mes.nome(mes).lowercased()) as contas e gastos passam da renda. Antes de adiantar, corte ou adie cobranças desse mês.")
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
                    Text("\(ganho) \(ganho == 1 ? "mês" : "meses") antes, adiantando até \(extra.moedaInteira) nos meses em que sobra dinheiro e usando o que cada dívida quitada libera.")
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

    private func descricao(_ d: Divida) -> String {
        var t = "\(d.restantes) \(d.restantes == 1 ? "parcela" : "parcelas")"
        if let p = d.proxima { t += " · próxima \(p.valor.moeda) em \(mesAno(p.mes))" }
        if d.juros > 0 { t += " · \(d.juros.formatted(.number.precision(.fractionLength(0...2)).locale(ptBR)))% a.m." }
        return t
    }

    /// "•••" de uma dívida: editar a próxima conta, remover a próxima parcela ou remover tudo
    private func menuDivida(_ d: Divida) -> some View {
        Menu {
            if let p = d.proxima {
                Button { editando = p.conta } label: { Label("Editar", systemImage: "pencil") }
                Button(role: .destructive) {
                    Exclusao.contaSoNoMes(p.conta, mes: p.mes, ctx: ctx)
                } label: { Label("Remover parcela de \(mesAno(p.mes))", systemImage: "calendar.badge.minus") }
            }
            Button(role: .destructive) {
                Exclusao.contas(d.contas, nome: d.nome, ctx: ctx)
            } label: { Label("Remover tudo (\(d.restantes)x)", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.cartao2, in: Circle())
        }
    }

    private func ordemQuitacao(_ ordem: [Divida], fimPlano: [String: Int], hoje: Int) -> some View {
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
                            Text(d.nome).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Spacer()
                            Text(d.total.moeda).font(.system(size: 15, weight: .bold))
                            menuDivida(d)
                        }
                        Text(descricao(d))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text("Termina \(mesAno(d.fim))").foregroundStyle(.secondary)
                            if let f = fimPlano[d.id], f < d.fim {
                                Text("→ \(mesAno(f)) com o plano").foregroundStyle(.green)
                            }
                        }
                        .font(.system(size: 12))
                        Button { adiantando = d } label: {
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
