import SwiftUI
import SwiftData

/// Apagar transações e contas sempre com a opção "Desfazer" logo em seguida
@MainActor
enum Exclusao {
    static func transacao(_ t: Transacao, ctx: ModelContext) {
        let copia = t.copia()
        let nome = t.titulo
        withAnimation {
            ctx.delete(t)
            try? ctx.save()
        }
        Notificacoes.reagendar(ctx)
        AppState.shared.oferecerDesfazer("\(nome) apagado") {
            ctx.insert(copia)
            try? ctx.save()
            Notificacoes.reagendar(ctx)
        }
    }

    /// Apaga a conta de todos os meses
    static func conta(_ c: Conta, ctx: ModelContext) {
        let copia = c.copia()
        let nome = c.nome
        withAnimation {
            ctx.delete(c)
            try? ctx.save()
        }
        Notificacoes.reagendar(ctx)
        AppState.shared.oferecerDesfazer("\(nome) apagada") {
            ctx.insert(copia)
            try? ctx.save()
            Notificacoes.reagendar(ctx)
        }
    }

    /// Apaga várias contas de uma vez (ex.: todas as "Nubank" de uma dívida)
    static func contas(_ lista: [Conta], nome: String, ctx: ModelContext) {
        let copias = lista.map { $0.copia() }
        withAnimation {
            for c in lista { ctx.delete(c) }
            try? ctx.save()
        }
        Notificacoes.reagendar(ctx)
        AppState.shared.oferecerDesfazer("\(nome) apagada") {
            for c in copias { ctx.insert(c) }
            try? ctx.save()
            Notificacoes.reagendar(ctx)
        }
    }

    /// Apaga a conta só daquele mês; os outros meses continuam
    static func contaSoNoMes(_ c: Conta, mes: Int, ctx: ModelContext) {
        withAnimation {
            c.excluir(em: mes)
            try? ctx.save()
        }
        Notificacoes.reagendar(ctx)
        AppState.shared.oferecerDesfazer("\(c.nome) apagada de \(Mes.nome(mes).lowercased())") {
            c.restaurar(em: mes)
            try? ctx.save()
            Notificacoes.reagendar(ctx)
        }
    }
}
