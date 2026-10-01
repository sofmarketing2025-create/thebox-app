import SwiftUI
import SwiftData

/// Orçamento do dia a dia: um valor pra cada dia da semana (seg R$ 50, ter R$ 30...) ou um total da semana.
/// O mês todo continua no "limite do mês" da aba Análise.
enum OrcamentoDia {
    private static var d: UserDefaults { .standard }
    static let nomesDias = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
    /// Ordem pra mostrar: segunda primeiro (índices = weekday - 1)
    static let ordem = [1, 2, 3, 4, 5, 6, 0]

    static var ativo: Bool { d.bool(forKey: "orcAtivo") }
    static var modo: String { d.string(forKey: "orcModo") ?? "dia" }
    static var porDia: [Double] {
        let a = d.array(forKey: "orcDias") as? [Double] ?? []
        return a.count == 7 ? a : Array(repeating: 0, count: 7)
    }
    static var semana: Double { d.double(forKey: "orcSemana") }

    static func inicioSemana(_ data: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: data)?.start ?? cal.startOfDay(for: data)
    }

    /// Limite, quanto já gastou e o nome do período ("de hoje", "da semana") na data
    static func situacao(em data: Date, transacoes: [Transacao]) -> (limite: Double, gasto: Double, nome: String)? {
        guard ativo else { return nil }
        let cal = Calendar.current
        let gastos = transacoes.filter { $0.tipo == .gasto && !$0.ehAjuste }
        if modo == "semana" {
            guard semana > 0 else { return nil }
            let ini = inicioSemana(data)
            let fim = cal.date(byAdding: .day, value: 7, to: ini) ?? data
            let g = gastos.filter { $0.data >= ini && $0.data < fim }.reduce(0) { $0 + $1.valor }
            return (semana, g, "da semana")
        }
        let limite = porDia[cal.component(.weekday, from: data) - 1]
        guard limite > 0 else { return nil }
        let g = gastos.filter { cal.isDate($0.data, inSameDayAs: data) }.reduce(0) { $0 + $1.valor }
        return (limite, g, cal.isDateInToday(data) ? "de hoje" : "do dia")
    }
}

extension Notificacoes {
    /// "Você gastou R$ 30. Já são 30% do seu orçamento de hoje" (30%, 50%, 80%, 90%, 100%)
    @MainActor
    static func verificarDiario(valor: Double, data: Date, ctx: ModelContext) {
        let ts = (try? ctx.fetch(FetchDescriptor<Transacao>())) ?? []
        guard let s = OrcamentoDia.situacao(em: data, transacoes: ts) else { return }
        let antes = s.gasto - valor
        guard let f = faixas.last(where: { antes < s.limite * $0 && s.gasto >= s.limite * $0 }) else { return }
        if f >= 1 {
            agora("Orçamento \(s.nome) estourado",
                  "Você gastou \(valor.moeda) agora e passou do limite: \(s.gasto.moeda) de \(s.limite.moeda).")
        } else {
            agora("\(porcento(f)) do orçamento \(s.nome)",
                  "Você gastou \(valor.moeda). Isso já é \(porcento(s.gasto / s.limite)) do seu orçamento \(s.nome) (\(s.limite.moeda)). Restam \((s.limite - s.gasto).moeda).")
        }
    }
}

/// Config → Orçamento do dia a dia
struct SecaoOrcamentoDia: View {
    @AppStorage("orcAtivo") private var ativo = false
    @AppStorage("orcModo") private var modo = "dia"
    @State private var valores: [String] = Array(repeating: "", count: 7)
    @State private var semanaTexto = ""
    @State private var carregado = false

    private func campo(_ i: Int) -> Binding<String> {
        Binding(get: { valores[i] }, set: { valores[i] = $0 })
    }

    var body: some View {
        Secao("Orçamento do dia a dia") {
            LinhaToggle(titulo: "Limite de gasto por dia ou semana",
                        sub: "Avisa quando chegar em 30%, 50%, 80%, 90% e 100%", ligado: $ativo)
            if ativo {
                Picker("Modo", selection: $modo) {
                    Text("Por dia").tag("dia")
                    Text("Por semana").tag("semana")
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 10)
                if modo == "dia" {
                    ForEach(OrcamentoDia.ordem, id: \.self) { i in
                        HStack {
                            Text(OrcamentoDia.nomesDias[i]).font(.system(size: 15))
                            Spacer()
                            Text(Moeda.atual.simbolo).foregroundStyle(.secondary)
                            TextField("0,00", text: campo(i))
                                .mascaraDinheiro(campo(i))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        .padding(.vertical, 7)
                    }
                    Button("Usar o valor de segunda em todos os dias") {
                        let seg = valores[1]
                        valores = Array(repeating: seg, count: 7)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 8)
                } else {
                    HStack {
                        Text("Total da semana").font(.system(size: 15))
                        Spacer()
                        Text(Moeda.atual.simbolo).foregroundStyle(.secondary)
                        TextField("0,00", text: $semanaTexto)
                            .mascaraDinheiro($semanaTexto)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    .padding(.vertical, 7)
                    Text("A semana vai de segunda a domingo.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("Conta os gastos do dia a dia (compras, Pix, maquininha). Contas fixas ficam de fora. O limite do mês todo continua na aba Análise.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .onAppear {
            guard !carregado else { return }
            valores = OrcamentoDia.porDia.map { textoDinheiro($0) }
            semanaTexto = textoDinheiro(OrcamentoDia.semana)
            carregado = true
        }
        .onChange(of: valores) { _, novos in
            UserDefaults.standard.set(novos.map { lerValor($0) ?? 0 }, forKey: "orcDias")
        }
        .onChange(of: semanaTexto) { _, novo in
            UserDefaults.standard.set(lerValor(novo) ?? 0, forKey: "orcSemana")
        }
    }
}

/// Home: orçamento de hoje (ou da semana) com o que já foi gasto
struct CartaoOrcamentoDia: View {
    let limite: Double
    let gasto: Double
    let nome: String

    var body: some View {
        let p = limite > 0 ? gasto / limite : 0
        let resta = limite - gasto
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("ORÇAMENTO \(nome.uppercased())")
                    .font(.system(size: 12, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Text(resta >= 0 ? "Resta \(resta.moeda)" : "Passou \(abs(resta).moeda)")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(resta < 0 ? Color.red : corPorcentagem(p))
            }
            BarraProgresso(p: p, cor: corPorcentagem(p), altura: 5)
            HStack {
                Text("Gastou \(gasto.moeda) de \(limite.moeda)")
                Spacer()
                Text(porcento(p)).fontWeight(.semibold)
            }
            .font(.system(size: 13))
        }
        .cartao(18)
    }
}
