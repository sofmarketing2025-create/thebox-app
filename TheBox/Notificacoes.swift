import Foundation
import SwiftData
import UserNotifications

enum Notificacoes {
    static func pedirPermissao() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Apaga os avisos agendados e agenda de novo para as contas não pagas dos próximos meses.
    @MainActor
    static func reagendar(_ ctx: ModelContext) {
        let contas = (try? ctx.fetch(FetchDescriptor<Conta>())) ?? []
        let d = UserDefaults.standard
        let ativo = d.object(forKey: "avisosAtivos") as? Bool ?? true
        let antes = d.object(forKey: "diasAntes") as? Int ?? 2
        let hora = d.object(forKey: "horaAviso") as? Int ?? 9

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard ativo else { return }

        let hoje = Mes.indice()
        let agora = Date.now
        var avisos: [(quando: Date, pedido: UNNotificationRequest)] = []

        for i in hoje...(hoje + 2) {
            for conta in contas where conta.ocorre(em: i) && !conta.pago(em: i) {
                let venc = Mes.data(i, dia: conta.dia, hora: hora)
                var momentos: [(Date, String)] = [(venc, "vence hoje")]
                if antes > 0, let antecipado = Calendar.current.date(byAdding: .day, value: -antes, to: venc) {
                    momentos.append((antecipado, antes == 1 ? "vence amanhã" : "vence em \(antes) dias"))
                }
                for (quando, texto) in momentos where quando > agora {
                    let conteudo = UNMutableNotificationContent()
                    conteudo.title = conta.nome
                    conteudo.body = "\(conta.valor.brl) \(texto)."
                    conteudo.sound = .default
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: quando)
                    let gatilho = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let pedido = UNNotificationRequest(identifier: UUID().uuidString, content: conteudo, trigger: gatilho)
                    avisos.append((quando, pedido))
                }
            }
        }

        // O iOS guarda no máximo 64 avisos pendentes por app
        for aviso in avisos.sorted(by: { $0.quando < $1.quando }).prefix(60) {
            center.add(aviso.pedido)
        }
    }
}
