import SwiftUI
import SwiftData

// MARK: - Assinaturas escondidas

/// Gasto que aparece uma vez por mês, no mesmo lugar, com valor parecido (ex.: Netflix, academia)
struct SugestaoAssinatura: Identifiable {
    let id: String
    let nome: String
    let valor: Double
    let dia: Int
    let categoria: String
    let meses: Int
}

enum Assinaturas {
    static func ignoradas() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "assinaturasIgnoradas") ?? [])
    }

    static func ignorar(_ id: String) {
        var lista = UserDefaults.standard.stringArray(forKey: "assinaturasIgnoradas") ?? []
        lista.append(id)
        UserDefaults.standard.set(lista, forKey: "assinaturasIgnoradas")
    }

    static func detectar(transacoes: [Transacao], contas: [Conta]) -> [SugestaoAssinatura] {
        let hoje = Mes.indice()
        let fora = ignoradas()
        let jaSaoContas = Set(contas.map { PlanoCalculo.chave($0.nome) })
        let recentes = transacoes.filter {
            $0.tipo == .gasto && !$0.ehAjuste && !$0.descricao.isEmpty && $0.mes >= hoje - 4 && $0.mes <= hoje
        }
        var r: [SugestaoAssinatura] = []
        for (chave, lista) in Dictionary(grouping: recentes, by: { PlanoCalculo.chave($0.descricao) })
        where !fora.contains(chave) && !jaSaoContas.contains(chave) {
            let porMes = Dictionary(grouping: lista, by: \.mes)
            // pelo menos 2 meses, uma compra por mês, valores parecidos (±15%)
            guard porMes.count >= 2, porMes.values.allSatisfy({ $0.count == 1 }) else { continue }
            let media = lista.reduce(0) { $0 + $1.valor } / Double(lista.count)
            guard media > 0, lista.allSatisfy({ abs($0.valor - media) / media <= 0.15 }),
                  let ultima = lista.max(by: { $0.data < $1.data }) else { continue }
            r.append(SugestaoAssinatura(id: chave, nome: ultima.descricao, valor: (media * 100).rounded() / 100,
                                        dia: Calendar.current.component(.day, from: ultima.data),
                                        categoria: ultima.categoria, meses: porMes.count))
        }
        return r.sorted { $0.valor > $1.valor }
    }
}

struct CartaoAssinaturas: View {
    @Environment(\.modelContext) private var ctx
    @Query private var transacoes: [Transacao]
    @Query private var contas: [Conta]
    @State private var versao = 0

    var body: some View {
        let _ = versao
        let lista = Assinaturas.detectar(transacoes: transacoes, contas: contas)
        if !lista.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("PARECEM ASSINATURAS", systemImage: "repeat")
                    .font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Text("Gastos que se repetem todo mês. Transforme em conta fixa pra o app avisar antes e contar no planejamento.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(lista) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.nome).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text("~\(s.valor.moeda) todo mês · visto em \(s.meses) meses")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Button("Virar conta fixa") { virarConta(s) }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sobreDestaque)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(Color.destaque, in: Capsule())
                            Button("Não é") {
                                Assinaturas.ignorar(s.id)
                                withAnimation { versao += 1 }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Color.cartao2, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                }
            }
            .cartao(20)
        }
    }

    private func virarConta(_ s: SugestaoAssinatura) {
        // começa no mês que vem pra não contar duas vezes a compra deste mês
        ctx.insert(Conta(nome: s.nome, valor: s.valor, dia: s.dia, venceMesSeguinte: false, categoria: s.categoria,
                         repetir: true, parcelaAtual: 0, totalParcelas: 0, inicio: Mes.indice() + 1))
        try? ctx.save()
        Notificacoes.reagendar(ctx)
        Notificacoes.agora("\(s.nome) virou conta fixa", "Você vai ser avisado antes de cada cobrança.")
        withAnimation { versao += 1 }
    }
}

// MARK: - Revisão da semana

struct RevisaoSemanaView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var transacoes: [Transacao]
    @Query private var contas: [Conta]

    var body: some View {
        let cal = Calendar.current
        let agora = Date.now
        let inicio = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: agora)) ?? agora
        let inicio4 = cal.date(byAdding: .day, value: -28, to: inicio) ?? agora
        let gastos = transacoes.filter { $0.tipo == .gasto && !$0.ehAjuste }
        let semana = gastos.filter { $0.data >= inicio }
        let total = semana.reduce(0) { $0 + $1.valor }
        let media = gastos.filter { $0.data >= inicio4 && $0.data < inicio }.reduce(0) { $0 + $1.valor } / 4
        let porCategoria = Dictionary(grouping: semana, by: \.categoria)
            .map { ItemValor(nome: $0.key, valor: $0.value.reduce(0) { $0 + $1.valor }) }
            .sorted { $0.valor > $1.valor }
        let porDia = Dictionary(grouping: semana) { cal.startOfDay(for: $0.data) }
            .map { (dia: $0.key, valor: $0.value.reduce(0) { $0 + $1.valor }) }
            .max { $0.valor < $1.valor }
        let limite7 = cal.date(byAdding: .day, value: 7, to: agora) ?? agora
        let hoje = Mes.indice()
        let proximas = contas.flatMap { c in
            [hoje, hoje + 1].compactMap { i -> (nome: String, valor: Double, venc: Date)? in
                guard c.ocorre(em: i), !c.pago(em: i) else { return nil }
                let v = c.vencimento(em: i)
                if v >= cal.startOfDay(for: agora) && v <= limite7 { return (nome: c.nome, valor: c.valor, venc: v) }
                return nil
            }
        }.sorted { $0.venc < $1.venc }

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(inicio.formatted(.dateTime.day().month(.abbreviated).locale(ptBR))) a \(agora.formatted(.dateTime.day().month(.abbreviated).locale(ptBR)))")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("GASTOU NA SEMANA").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Text(total.moeda).font(.system(size: 32, weight: .heavy))
                        if media > 0 {
                            let dif = (total - media) / media
                            Label("\(porcento(abs(dif))) \(dif <= 0 ? "a menos" : "a mais") que a média (\(media.moeda)/semana)",
                                  systemImage: dif <= 0 ? "arrow.down.right" : "arrow.up.right")
                                .font(.system(size: 14))
                                .foregroundStyle(dif <= 0 ? Color.green : Color.orange)
                        }
                    }
                    .cartao(20)

                    if !porCategoria.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ONDE MAIS PESOU").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                            ForEach(porCategoria.prefix(3)) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(item.nome).font(.system(size: 15, weight: .medium))
                                        Spacer()
                                        Text(item.valor.moeda).font(.system(size: 15, weight: .semibold))
                                    }
                                    BarraProgresso(p: total > 0 ? item.valor / total : 0, cor: .primary, altura: 4)
                                }
                            }
                            if let d = porDia {
                                Text("Dia que mais gastou: \(d.dia.formatted(.dateTime.weekday(.wide).day().locale(ptBR))) (\(d.valor.moeda))")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 4)
                            }
                        }
                        .cartao(20)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("VENCE NOS PRÓXIMOS 7 DIAS").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        if proximas.isEmpty {
                            Text("Nenhuma conta. Semana tranquila.").font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        ForEach(proximas.indices, id: \.self) { i in
                            HStack {
                                Text(proximas[i].nome).font(.system(size: 15))
                                Spacer()
                                Text(proximas[i].venc.formatted(.dateTime.weekday(.abbreviated).day().locale(ptBR)))
                                    .font(.system(size: 13)).foregroundStyle(.secondary)
                                Text(proximas[i].valor.moeda).font(.system(size: 15, weight: .semibold))
                            }
                        }
                    }
                    .cartao(20)

                    Text(dica(total: total, media: media, top: porCategoria.first?.nome))
                        .font(.system(size: 14))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cartao2.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
            }
            .background(Color.fundo)
            .navigationTitle("Revisão da semana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .folha()
    }

    private func dica(total: Double, media: Double, top: String?) -> String {
        if total == 0 { return "💡 Nenhum gasto registrado na semana. Se gastou, use o toque duplo ou diga \"E aí Siri, gastei no LBO Finanças\"." }
        if media > 0 && total > media * 1.1, let top {
            return "💡 Semana acima da média. Segura \(top) nos próximos dias pra voltar pro ritmo."
        }
        return "💡 Bom ritmo. O que sobrar no fim do mês pode ir pra uma caixinha ou pra adiantar uma parcela."
    }
}

// MARK: - Fechamento do mês

struct FechamentoMesView: View {
    let mes: Int
    @Environment(\.dismiss) private var dismiss
    @Query private var transacoes: [Transacao]
    @Query private var contas: [Conta]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]

    var body: some View {
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
        let doMes = fin.transacoes(em: mes)
        let entrou = doMes.filter { $0.tipo == .receita && !$0.ehAjuste }.reduce(0) { $0 + $1.valor }
        let gastou = fin.gastoTotal(em: mes)
        let gastouAntes = fin.gastoTotal(em: mes - 1)
        let quitado = contas.filter { PlanoCalculo.temFim($0) && $0.ocorre(em: mes) && $0.pago(em: mes) }
            .reduce(0) { $0 + $1.valor }
            + doMes.filter { $0.descricao.hasPrefix("Adiantamento:") || $0.descricao.hasPrefix("Quitação à vista:") }
            .reduce(0) { $0 + $1.valor }
        let guardado = doMes.filter { $0.nomeCaixinha != nil }.reduce(0) { $0 + ($1.entrada ? -$1.valor : $1.valor) }
        let maior = fin.gastoPorCategoria(em: mes).max { $0.value < $1.value }
        let dividas = PlanoCalculo.dividas(contas, hoje: Mes.indice())
        let resta = dividas.reduce(0) { $0 + $1.total }
        let livre = dividas.map(\.fim).max()

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        bloco("Entrou", entrou.moeda, .green)
                        bloco("Saiu", gastou.moeda, .primary)
                    }
                    HStack(spacing: 12) {
                        bloco("Quitou", quitado.moeda, .primary)
                        bloco("Guardou", guardado.moeda, guardado >= 0 ? .primary : .orange)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COMO FOI").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        if entrou > 0 {
                            let sobra = entrou - gastou - max(guardado, 0)
                            linha(sobra >= 0 ? "Sobrou \(sobra.moeda) depois de tudo." : "Faltou \(abs(sobra).moeda): gastou mais do que entrou.",
                                  sobra >= 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                  sobra >= 0 ? .green : .orange)
                        }
                        if gastouAntes > 0 {
                            let dif = (gastou - gastouAntes) / gastouAntes
                            linha("Gastou \(porcento(abs(dif))) \(dif <= 0 ? "a menos" : "a mais") que em \(Mes.nome(mes - 1).lowercased()).",
                                  dif <= 0 ? "arrow.down.right" : "arrow.up.right", dif <= 0 ? .green : .orange)
                        }
                        if let maior {
                            linha("Onde mais pesou: \(maior.key) (\(maior.value.moeda)).", "chart.pie.fill", .secondary)
                        }
                    }
                    .cartao(20)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SUAS DÍVIDAS HOJE").font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Text(resta.moeda).font(.system(size: 26, weight: .heavy))
                        if let livre {
                            Text("Livre em \(Mes.nome(livre).lowercased()) de \(String(Mes.ano(livre))). Adiantar parcelas puxa essa data pra trás.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            Text("Nenhuma dívida com fim cadastrada. 🎉").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .cartao(20)
                }
                .padding(20)
            }
            .background(Color.fundo)
            .navigationTitle("Fechamento de \(Mes.nome(mes).lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .folha()
    }

    private func bloco(_ titulo: String, _ valor: String, _ cor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
            Text(valor).font(.system(size: 18, weight: .bold)).foregroundStyle(cor).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cartao(16)
    }

    private func linha(_ texto: String, _ icone: String, _ cor: Color) -> some View {
        Label {
            Text(texto).font(.system(size: 14))
        } icon: {
            Image(systemName: icone).foregroundStyle(cor)
        }
    }
}

// MARK: - Tendências por categoria

/// "Mercado caiu 15% em 3 meses": último mês fechado contra a média dos 3 anteriores
struct CartaoTendencias: View {
    let mes: Int
    @Query private var transacoes: [Transacao]
    @Query private var contas: [Conta]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]

    private struct Tendencia: Identifiable {
        let nome: String
        let antes: Double
        let agora: Double
        var id: String { nome }
        var dif: Double { antes > 0 ? (agora - antes) / antes : 1 }
    }

    var body: some View {
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
        let base = mes >= Mes.indice() ? Mes.indice() - 1 : mes
        let temHistorico = (1...3).contains { fin.temDados(em: base - $0) }
        let atual = fin.gastoPorCategoria(em: base)
        let anteriores = (1...3).map { fin.gastoPorCategoria(em: base - $0) }
        let mesesComDados = max(1, (1...3).filter { fin.temDados(em: base - $0) }.count)
        let nomes = Set(atual.keys).union(anteriores.flatMap(\.keys))
        let lista = nomes.compactMap { n -> Tendencia? in
            let media = anteriores.reduce(0) { $0 + ($1[n] ?? 0) } / Double(mesesComDados)
            let agora = atual[n] ?? 0
            guard max(media, agora) >= 20 else { return nil }
            let t = Tendencia(nome: n, antes: media, agora: agora)
            return abs(t.dif) >= 0.1 ? t : nil
        }
        .sorted { abs($0.dif) > abs($1.dif) }

        VStack(alignment: .leading, spacing: 10) {
            Label("TENDÊNCIAS POR CATEGORIA", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
            if !temHistorico {
                Text("Aparece quando tiver pelo menos 2 meses de gastos registrados. Aí você vê, por exemplo, \"Mercado caiu 15% em 3 meses\".")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else if lista.isEmpty {
                Text("Seus gastos em \(Mes.nome(base).lowercased()) ficaram parecidos com a média dos meses anteriores.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                ForEach(lista.prefix(5)) { t in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: t.dif < 0 ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                            .foregroundStyle(t.dif < 0 ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(t.nome) \(t.dif < 0 ? "caiu" : "subiu") \(porcento(abs(t.dif)))")
                                .font(.system(size: 14, weight: .semibold))
                            Text("média de \(t.antes.moedaInteira) → \(t.agora.moedaInteira) em \(Mes.nome(base).lowercased())")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Comparando \(Mes.nome(base).lowercased()) com a média dos \(mesesComDados) meses anteriores.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .cartao(20)
    }
}
