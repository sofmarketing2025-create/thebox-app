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

    /// Avisa quando uma categoria passa de 80% ou de 100% do limite
    @MainActor
    static func verificarLimite(categoria: String, valor: Double, data: Date, ctx: ModelContext) {
        guard ligado("alertasInteligentes") else { return }
        let cats = (try? ctx.fetch(FetchDescriptor<Categoria>())) ?? []
        guard let cat = cats.first(where: { $0.nome == categoria && $0.tipo == .gasto }), cat.limite > 0 else { return }
        let fin = Financas(transacoes: (try? ctx.fetch(FetchDescriptor<Transacao>())) ?? [],
                           contas: (try? ctx.fetch(FetchDescriptor<Conta>())) ?? [],
                           carteiras: (try? ctx.fetch(FetchDescriptor<Carteira>())) ?? [])
        let total = fin.gastoPorCategoria(em: Mes.indice(data))[categoria] ?? 0
        let antes = total - valor
        if antes < cat.limite && total >= cat.limite {
            agora("Limite atingido — \(categoria)",
                  "Você atingiu 100% do orçamento de \(categoria) (\(cat.limite.moeda)).")
        } else if antes < cat.limite * 0.8 && total >= cat.limite * 0.8 {
            agora("Quase no limite — \(categoria)",
                  "Você já usou \(porcento(total / cat.limite)) do orçamento de \(categoria) (\(cat.limite.moeda)).")
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
        var avisos: [(quando: Date, titulo: String, corpo: String)] = []

        let transacoes = (try? ctx.fetch(FetchDescriptor<Transacao>())) ?? []
        let contas = (try? ctx.fetch(FetchDescriptor<Conta>())) ?? []
        let carteiras = (try? ctx.fetch(FetchDescriptor<Carteira>())) ?? []
        let fin = Financas(transacoes: transacoes, contas: contas, carteiras: carteiras)

        if ligado("avisoContas") {
            let hoje = Mes.indice()
            for i in hoje...(hoje + 2) {
                var itens: [(nome: String, valor: Double, venc: Date, fatura: Bool)] = []
                for conta in contas where conta.ocorre(em: i) && !conta.pago(em: i) {
                    itens.append((conta.nome, conta.valor, conta.vencimento(em: i, hora: hora), false))
                }
                for cartao in fin.cartoes() where !cartao.faturaPaga(em: i) {
                    let v = fin.fatura(cartao, em: i)
                    if v > 0 { itens.append(("Fatura \(cartao.nome)", v, Mes.data(i, dia: cartao.diaVencimento, hora: hora), true)) }
                }
                for item in itens {
                    avisos.append((item.venc, item.fatura ? "Fatura chegando" : item.nome, "\(item.valor.moeda) vence hoje."))
                    for antes in dias {
                        guard let antecipado = cal.date(byAdding: .day, value: -antes, to: item.venc) else { continue }
                        let quando = antes == 1 ? "amanhã" : "em \(antes) dias"
                        let corpo = item.fatura
                            ? "Sua \(item.nome.lowercased()) vence \(quando) (\(item.valor.moeda))."
                            : "\(item.valor.moeda) vence \(quando)."
                        avisos.append((antecipado, item.fatura ? "Fatura chegando" : item.nome, corpo))
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
                let gastos = transacoes.filter { $0.tipo == .gasto }
                let semana = gastos.filter { $0.data >= inicio }.reduce(0) { $0 + $1.valor }
                let media = gastos.filter { $0.data >= inicio4 && $0.data < inicio }.reduce(0) { $0 + $1.valor } / 4
                var corpo = "Você gastou \(semana.moeda) essa semana."
                if media > 0 {
                    let dif = (semana - media) / media
                    corpo = "Você gastou \(semana.moeda) essa semana, \(porcento(abs(dif))) \(dif <= 0 ? "a menos" : "a mais") que a média."
                }
                avisos.append((domingo, "Resumo da semana", corpo))
            }
        }

        for aviso in avisos.filter({ $0.quando > agora }).sorted(by: { $0.quando < $1.quando }).prefix(58) {
            let c = UNMutableNotificationContent()
            c.title = aviso.titulo
            c.body = aviso.corpo
            c.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: aviso.quando)
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        if ligado("lembreteRegistro") {
            let c = UNMutableNotificationContent()
            c.title = "Registrou seus gastos de hoje?"
            c.body = "Leva dois segundos: toque duas vezes nas costas do iPhone."
            c.sound = .default
            center.add(UNNotificationRequest(identifier: "lembrete-diario", content: c,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 30),
                                                                                    repeats: true)))
        }
    }
}
