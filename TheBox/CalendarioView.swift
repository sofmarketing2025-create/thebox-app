import SwiftUI
import SwiftData

/// Um compromisso ou entrada num dia do mês
struct EventoDia: Identifiable {
    enum Tipo { case conta, fatura, receita }
    let id = UUID()
    let dia: Int
    let nome: String
    let valor: Double
    let tipo: Tipo
    let pago: Bool
}

/// Calendário do mês com o dia do salário e os vencimentos. Mostra em vermelho os dias em que
/// as contas vencidas até ali passam do que já entrou (ex.: conta dia 1, salário dia 5).
struct CalendarioView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var contas: [Conta]
    @Query private var recorrencias: [Recorrencia]
    @Query private var transacoes: [Transacao]
    @Query(sort: \Carteira.ordem) private var carteiras: [Carteira]
    @State private var mes: Int
    @State private var diaSelecionado: Int?

    init(mes: Int) {
        _mes = State(initialValue: mes)
    }

    private func eventos() -> [EventoDia] {
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)
        let cal = Calendar.current
        var r: [EventoDia] = []
        for c in contas {
            for i in [mes - 1, mes] where c.ocorre(em: i) {
                let venc = c.vencimento(em: i)
                if Mes.indice(venc) == mes {
                    r.append(EventoDia(dia: cal.component(.day, from: venc), nome: c.nome, valor: c.valor,
                                       tipo: .conta, pago: c.pago(em: i)))
                }
            }
        }
        for c in fin.cartoes() {
            let v = fin.fatura(c, em: mes)
            if v > 0 {
                r.append(EventoDia(dia: cal.component(.day, from: Mes.data(mes, dia: c.diaVencimento)),
                                   nome: "Fatura \(c.nome)", valor: v, tipo: .fatura, pago: c.faturaPaga(em: mes)))
            }
        }
        for rec in recorrencias where rec.ativa && mes > rec.ultimoMes {
            r.append(EventoDia(dia: cal.component(.day, from: Mes.data(mes, dia: rec.dia)),
                               nome: "\(rec.nome) (previsto)", valor: rec.valor, tipo: .receita, pago: false))
        }
        for t in fin.transacoes(em: mes) where t.tipo == .receita {
            r.append(EventoDia(dia: cal.component(.day, from: t.data), nome: t.titulo, valor: t.valor,
                               tipo: .receita, pago: true))
        }
        return r
    }

    var body: some View {
        let lista = eventos()
        let primeiro = Mes.data(mes, dia: 1, hora: 12)
        let cal = Calendar.current
        let diasNoMes = cal.range(of: .day, in: .month, for: primeiro)?.count ?? 30
        let vazios = cal.component(.weekday, from: primeiro) - 1
        // saldo acumulado dia a dia: entradas − contas/faturas que vencem até aquele dia
        var acumulado: [Int: Double] = [:]
        var soma = 0.0
        for d in 1...diasNoMes {
            for e in lista where e.dia == d { soma += e.tipo == .receita ? e.valor : -e.valor }
            acumulado[d] = soma
        }
        let entradas = lista.filter { $0.tipo == .receita }.reduce(0) { $0 + $1.valor }
        let saidas = lista.filter { $0.tipo != .receita }.reduce(0) { $0 + $1.valor }
        let primeiroNegativo = (1...diasNoMes).first { (acumulado[$0] ?? 0) < -0.01 }

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button { mes -= 1; diaSelecionado = nil } label: { Image(systemName: "chevron.left").padding(10) }
                        Spacer()
                        Text("\(Mes.nome(mes)) \(String(Mes.ano(mes)))").font(.system(size: 18, weight: .bold))
                        Spacer()
                        Button { mes += 1; diaSelecionado = nil } label: { Image(systemName: "chevron.right").padding(10) }
                    }
                    .buttonStyle(.plain)

                    resumo(entradas: entradas, saidas: saidas, primeiroNegativo: primeiroNegativo, lista: lista,
                           acumulado: acumulado, diasNoMes: diasNoMes)

                    grade(lista: lista, diasNoMes: diasNoMes, vazios: vazios, acumulado: acumulado)

                    detalhe(lista: lista, acumulado: acumulado)
                }
                .padding(20)
            }
            .background(Color.cartao)
            .navigationTitle("Calendário")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
        .folha()
    }

    // MARK: Partes

    private func resumo(entradas: Double, saidas: Double, primeiroNegativo: Int?, lista: [EventoDia],
                        acumulado: [Int: Double], diasNoMes: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entra").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(entradas.moeda).font(.system(size: 16, weight: .bold)).foregroundStyle(.green)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Contas e faturas").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(saidas.moeda).font(.system(size: 16, weight: .bold))
                }
            }
            if let d = primeiroNegativo {
                let proximaEntrada = lista.filter { $0.tipo == .receita && $0.dia > d }.map(\.dia).min()
                let falta = abs(acumulado[d] ?? 0)
                Label {
                    Text(proximaEntrada.map { "Do dia \(d) ao dia \($0) as contas passam do que entrou: faltam \(falta.moeda). Guarde antes ou peça pra mudar o vencimento pra depois do dia \($0)." }
                         ?? "A partir do dia \(d) as contas passam do que entrou neste mês: faltam \(falta.moeda).")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.system(size: 13))
            } else if entradas > 0 {
                Label("Todas as contas do mês vencem com dinheiro já na conta.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            } else {
                Text("Registre sua renda (Receita) com a data em que cai pra ver se as contas vencem antes dela.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.cartao2.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func grade(lista: [EventoDia], diasNoMes: Int, vazios: Int, acumulado: [Int: Double]) -> some View {
        let colunas = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let hoje = Calendar.current.component(.day, from: .now)
        let ehMesAtual = mes == Mes.indice()
        return LazyVGrid(columns: colunas, spacing: 6) {
            ForEach(["D", "S", "T", "Q", "Q", "S", "S"].indices, id: \.self) { i in
                Text(["D", "S", "T", "Q", "Q", "S", "S"][i])
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            ForEach(0..<vazios, id: \.self) { _ in Color.clear.frame(height: 48) }
            ForEach(1...diasNoMes, id: \.self) { d in
                let doDia = lista.filter { $0.dia == d }
                let temConta = doDia.contains { $0.tipo != .receita && !$0.pago }
                let temPaga = doDia.contains { $0.tipo != .receita && $0.pago }
                let temEntrada = doDia.contains { $0.tipo == .receita }
                let negativo = (acumulado[d] ?? 0) < -0.01 && temConta
                let selecionado = diaSelecionado == d
                Button {
                    diaSelecionado = selecionado ? nil : d
                } label: {
                    VStack(spacing: 3) {
                        Text("\(d)")
                            .font(.system(size: 14, weight: ehMesAtual && d == hoje ? .heavy : .medium))
                            .foregroundStyle(selecionado ? Color.sobreDestaque : Color.primary)
                        HStack(spacing: 3) {
                            if temEntrada { Circle().fill(Color.green).frame(width: 6, height: 6) }
                            if temConta { Circle().fill(negativo ? Color.red : Color.orange).frame(width: 6, height: 6) }
                            if temPaga && !temConta { Circle().fill(Color.secondary).frame(width: 6, height: 6) }
                        }
                        .frame(height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        selecionado ? Color.destaque : (negativo ? Color.red.opacity(0.18) : Color.cartao2.opacity(0.35)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ehMesAtual && d == hoje ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func detalhe(lista: [EventoDia], acumulado: [Int: Double]) -> some View {
        let dias = diaSelecionado.map { [$0] } ?? Array(Set(lista.map(\.dia))).sorted()
        HStack(spacing: 14) {
            Legenda(cor: .green, texto: "entra")
            Legenda(cor: .orange, texto: "a pagar")
            Legenda(cor: .red, texto: "falta dinheiro")
        }
        .font(.system(size: 12))
        if dias.isEmpty {
            Text("Nenhuma conta ou receita neste mês.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        ForEach(dias, id: \.self) { d in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Dia \(d)").font(.system(size: 14, weight: .bold))
                    Spacer()
                    Text("saldo do mês até aqui: \((acumulado[d] ?? 0).moeda)")
                        .font(.system(size: 12))
                        .foregroundStyle((acumulado[d] ?? 0) < 0 ? Color.red : Color.secondary)
                }
                ForEach(lista.filter { $0.dia == d }) { e in
                    HStack {
                        Image(systemName: e.tipo == .receita ? "arrow.down.circle.fill" : (e.tipo == .fatura ? "creditcard.fill" : "doc.text.fill"))
                            .foregroundStyle(e.tipo == .receita ? Color.green : (e.pago ? Color.secondary : Color.orange))
                        Text(e.nome).font(.system(size: 14)).lineLimit(1)
                        if e.pago && e.tipo != .receita { Chip("pago") }
                        Spacer()
                        Text((e.tipo == .receita ? "+" : "-") + e.valor.moeda)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(e.tipo == .receita ? Color.green : Color.primary)
                    }
                }
            }
            .padding(14)
            .background(Color.cartao2.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
