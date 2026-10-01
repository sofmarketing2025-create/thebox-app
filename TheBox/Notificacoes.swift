import Foundation
import SwiftData
import UserNotifications

enum Notificacoes {
    private static func ligado(_ chave: String) -> Bool {
        UserDefaults.standard.object(forKey: chave) as? Bool ?? true
    }

    /// Dias de antecedência dos avisos de conta (ex.: [1, 3, 5]). Salvo como "1,3,5".
    static func diasAviso() -> [Int] {
        let d = UserDefaults.standard
        let texto = d.string(forKey: "diasAviso") ?? ""
        if texto.isEmpty {
            let antigo = d.object(forKey: "diasAntes") as? Int ?? 1
            return antigo > 0 ? [antigo] : []
        }
        return Array(Set(texto.split(separator: ",").compactMap { Int($0) }.filter { $0 > 0 })).sorted()
    }

    static func salvarDiasAviso(_ dias: [Int]) {
        UserDefaults.standard.set(Array(Set(dias)).sorted().map(String.init).joined(separator: ","), forKey: "diasAviso")
    }

    static func pedirPermissao() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Aviso na hora (aparece no topo mesmo com o app aberto)
    static func agora(_ titulo: String, _ corpo: String) {
        let c = UNMutableNotificationContent()
        c.title = titulo
        c.body = corpo
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// "R$ 20,00 registrado — Teste · Alimentação"
    static func registrado(valor: Double, titulo: String, categoria: String) {
        agora("\(valor.moeda) registrado", "\(titulo) · \(categoria)")
    }

    /// Faixas em que o app avisa (30%, 50%, 80%, 90% e 100% do limite)
    static let faixas: [Double] = [0.3, 0.5, 0.8, 0.9, 1.0]

    /// Maior faixa que foi cruzada agora (antes estava abaixo, agora está em cima ou acima)
    private static func faixaCruzada(antes: Double, depois: Double, limite: Double) -> Double? {
        guard limite > 0 else { return nil }
        return faixas.last { antes < limite * $0 && depois >= limite * $0 }
    }

    private static func textoFaixa(_ f: Double, nome: String, gasto: Double, limite: Double) -> (String, String) {
        if f >= 1 {
            return ("Limite atingido — \(nome)",
                    "Você usou \(porcento(gasto / limite)) do orçamento de \(nome): \(gasto.moeda) de \(limite.moeda).")
        }
        let titulo = f >= 0.8 ? "Quase no limite — \(nome)" : "\(porcento(f)) do orçamento — \(nome)"
        return (titulo, "Você já usou \(porcento(gasto / limite)) de \(nome): \(gasto.moeda) de \(limite.moeda). Restam \((limite - gasto).moeda).")
    }

    /// Avisa quando a categoria ou o orçamento do mês passa de 30%, 50%, 80%, 90% ou 100%
    @MainActor
    static func verificarLimite(categoria: String, valor: Double, data: Date, ctx: ModelContext) {
        verificarDiario(valor: valor, data: data, ctx: ctx)
        guard ligado("alertasInteligentes") else { return }
        let fin = Financas(transacoes: (try? ctx.fetch(FetchDescriptor<Transacao>())) ?? [],
                           contas: (try? ctx.fetch(FetchDescriptor<Conta>())) ?? [],
                           carteiras: (try? ctx.fetch(FetchDescriptor<Carteira>())) ?? [],
                           limites: (try? ctx.fetch(FetchDescriptor<LimiteMensal>())) ?? [])
        let mes = Mes.indice(data)

        // Categoria
        let cats = (try? ctx.fetch(FetchDescriptor<Categoria>())) ?? []
        if let cat = cats.first(where: { $0.nome == categoria && $0.tipo == .gasto }), cat.limite > 0 {
            let total = fin.gastoPorCategoria(em: mes)[categoria] ?? 0
            if let f = faixaCruzada(antes: total - valor, depois: total, limite: cat.limite) {
                let t = textoFaixa(f, nome: categoria, gasto: total, limite: cat.limite)
                agora(t.0, t.1)
            }
        }

        // Orçamento total do mês
        let limiteMes = fin.limite(em: mes)
        if limiteMes > 0 {
            let total = fin.gastoTotal(em: mes)
            if let f = faixaCruzada(antes: total - valor, depois: total, limite: limiteMes) {
                let nomeMes = Mes.nome(mes).lowercased()
                if f >= 1 {
                    agora("Orçamento do mês atingido",
                          "Você já gastou \(total.moeda) de \(limiteMes.moeda) em \(nomeMes).")
                } else {
                    agora("\(porcento(f)) do orçamento do mês",
                          "Você já gastou \(total.moeda) de \(limiteMes.moeda) em \(nomeMes). Restam \((limiteMes - total).moeda).")
                }
            }
        }
    }

    /// Refaz todos os avisos agendados: contas, faturas, lembrete diário e resumo da semana
    @MainActor
    static func reagendar(_ ctx: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let d = UserDefaults.standard
        let dias = diasAviso()
        let hora = d.object(forKey: "horaAviso") as? Int ?? 9
        let agora = Date.now
        let cal = Calendar.current
        var avisos: [Aviso] = []

        let transacoes = (try? ctx.fetch(FetchDescriptor<Transacao>())) ?? []
        let contas = (try? ctx.fetch(FetchDescriptor<Conta>())) ?? []
        let carteiras = (try? ctx.fetch(FetchDescriptor<Carteira>())) ?? []
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)

        if ligado("avisoContas") {
            let hoje = Mes.indice()
            // Olha meses suficientes pra caber o aviso mais antecipado (ex.: 90 dias antes)
            let meses = max(2, (dias.max() ?? 0) / 30 + 2)
            for i in hoje...(hoje + meses) {
                var itens: [(nome: String, valor: Double, venc: Date, fatura: Bool, info: [String: String])] = []
                for conta in contas where conta.ocorre(em: i) && !conta.pago(em: i) {
                    itens.append((conta.nome, conta.valor, conta.vencimento(em: i, hora: hora), false,
                                  ["conta": conta.chave.uuidString, "mes": String(i)]))
                }
                for cartao in fin.cartoes() where !cartao.faturaPaga(em: i) {
                    let v = fin.fatura(cartao, em: i)
                    if v > 0 {
                        itens.append(("Fatura \(cartao.nome)", v, Mes.data(i, dia: cartao.diaVencimento, hora: hora), true,
                                      ["cartao": cartao.chave.uuidString, "mes": String(i)]))
                    }
                }
                for item in itens {
                    let titulo = item.fatura ? "Fatura chegando" : item.nome
                    avisos.append(Aviso(quando: item.venc, titulo: titulo, corpo: "\(item.valor.moeda) vence hoje.",
                                        info: item.info, categoria: "conta"))
                    for antes in dias {
                        guard let antecipado = cal.date(byAdding: .day, value: -antes, to: item.venc) else { continue }
                        let quando = antes == 1 ? "amanhã" : "em \(antes) dias"
                        let corpo = item.fatura
                            ? "Sua \(item.nome.lowercased()) vence \(quando) (\(item.valor.moeda))."
                            : "\(item.valor.moeda) vence \(quando)."
                        avisos.append(Aviso(quando: antecipado, titulo: titulo, corpo: corpo, info: item.info, categoria: "conta"))
                    }
                }
            }
        }

        if ligado("resumoSemana") {
            var comps = DateComponents()
            comps.weekday = 1
            comps.hour = 19
            if let domingo = cal.nextDate(after: agora, matching: comps, matchingPolicy: .nextTime),
               let inicio = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: domingo)),
               let inicio4 = cal.date(byAdding: .day, value: -28, to: inicio) {
                let gastos = transacoes.filter { $0.tipo == .gasto && !$0.ehAjuste }
                let semana = gastos.filter { $0.data >= inicio }.reduce(0) { $0 + $1.valor }
                let media = gastos.filter { $0.data >= inicio4 && $0.data < inicio }.reduce(0) { $0 + $1.valor } / 4
                var corpo = "Você gastou \(semana.moeda) essa semana."
                if media > 0 {
                    let dif = (semana - media) / media
                    corpo = "Você gastou \(semana.moeda) essa semana, \(porcento(abs(dif))) \(dif <= 0 ? "a menos" : "a mais") que a média."
                }
                avisos.append(Aviso(quando: domingo, titulo: "Resumo da semana", corpo: corpo + " Toque pra revisar.",
                                    info: ["abrir": "revisao"], categoria: nil))
            }
        }

        // Fechamento do mês: dia 1º às 10h
        if let proximoMes = cal.date(byAdding: .month, value: 1, to: agora) {
            var c = cal.dateComponents([.year, .month], from: proximoMes)
            c.day = 1
            c.hour = 10
            if let quando = cal.date(from: c) {
                let mesFechado = Mes.indice(agora)
                avisos.append(Aviso(quando: quando, titulo: "Fechamento de \(Mes.nome(mesFechado).lowercased())",
                                    corpo: "Veja quanto entrou, saiu, quanto você quitou e guardou no mês.",
                                    info: ["abrir": "fechamento", "mes": String(mesFechado)], categoria: nil))
            }
        }

        for aviso in avisos.filter({ $0.quando > agora }).sorted(by: { $0.quando < $1.quando }).prefix(58) {
            let c = UNMutableNotificationContent()
            c.title = aviso.titulo
            c.body = aviso.corpo
            c.sound = .default
            c.userInfo = aviso.info
            if let cat = aviso.categoria { c.categoryIdentifier = cat }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: aviso.quando)
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        if ligado("lembreteRegistro") {
            let c = UNMutableNotificationContent()
            c.title = "Registrou seus gastos de hoje?"
            c.body = "Leva dois segundos: toque duas vezes nas costas do iPhone ou diga \"E aí Siri, gastei no LBO Finanças\"."
            c.sound = .default
            center.add(UNNotificationRequest(identifier: "lembrete-diario", content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 30),
                                                                                    repeats: true)))
        }
    }

    struct Aviso {
        let quando: Date
        let titulo: String
        let corpo: String
        let info: [String: String]
        let categoria: String?
    }

    /// Botão "Paguei" nos avisos de conta e fatura
    static func registrarCategorias() {
        let paguei = UNNotificationAction(identifier: "paguei", title: "Paguei", options: [])
        let conta = UNNotificationCategory(identifier: "conta", actions: [paguei], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([conta])
    }

    /// Toque no aviso ou no botão "Paguei"
    @MainActor
    static func tratar(acao: String, info: [AnyHashable: Any]) {
        let mes = (info["mes"] as? String).flatMap { Int($0) }
        if acao == "paguei", let container = Store.atual, let mes {
            let ctx = container.mainContext
            if let id = (info["conta"] as? String).flatMap(UUID.init(uuidString:)),
               let conta = try? ctx.fetch(FetchDescriptor<Conta>(predicate: #Predicate { $0.chave == id })).first {
                let carteiras = (try? ctx.fetch(FetchDescriptor<Carteira>(sortBy: [SortDescriptor(\.ordem)]))) ?? []
                let pagou = carteiras.first { $0.tipo == .pix }?.nome ?? carteiras.first { $0.tipo != .credito }?.nome ?? ""
                conta.marcarPago(em: mes, carteira: pagou)
                try? ctx.save()
                agora("\(conta.nome) marcada como paga", "\(conta.valor.moeda) · \(Mes.nome(mes).lowercased())")
            } else if let id = (info["cartao"] as? String).flatMap(UUID.init(uuidString:)),
                      let cartao = try? ctx.fetch(FetchDescriptor<Carteira>(predicate: #Predicate { $0.chave == id })).first,
                      !cartao.faturaPaga(em: mes) {
                cartao.alternarFatura(em: mes)
                try? ctx.save()
                agora("Fatura \(cartao.nome) marcada como paga", Mes.nome(mes))
            }
            reagendar(ctx)
            return
        }
        switch info["abrir"] as? String {
        case "revisao": AppState.shared.abrirRevisao = true
        case "fechamento": AppState.shared.abrirFechamento = mes ?? (Mes.indice() - 1)
        default: break
        }
    }
}
