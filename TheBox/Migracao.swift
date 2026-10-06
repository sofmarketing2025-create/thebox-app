import Foundation
import SwiftData

/// Ajustes de dados que rodam uma vez só depois de uma atualização
@MainActor
enum Migracao {
    /// O saldo agora passa de um mês pro outro. Quem já tinha ajustado o saldo neste mês
    /// (quando cada mês começava do zero) teria o dinheiro contado duas vezes: troca os ajustes
    /// do mês por um só, pra o saldo continuar exatamente o mesmo de antes.
    static func saldoAcumulado(_ ctx: ModelContext) {
        let chave = "migracaoSaldoAcumulado-" + (UserDefaults.standard.string(forKey: "uidAtual") ?? "")
        guard !UserDefaults.standard.bool(forKey: chave) else { return }
        let fin = Financas(transacoes: (try? ctx.fetch(FetchDescriptor<Transacao>())) ?? [],
                           contas: (try? ctx.fetch(FetchDescriptor<Conta>())) ?? [],
                           carteiras: (try? ctx.fetch(FetchDescriptor<Carteira>())) ?? [])
        let mes = Mes.indice()
        let ajustes = fin.transacoes(em: mes).filter(\.ehAjuste)
        if !ajustes.isEmpty {
            let liquido = fin.ajustes(em: mes) - fin.abertura(em: mes)
            for t in ajustes { ctx.delete(t) }
            if abs(liquido) >= 0.01 {
                ctx.insert(Transacao(tipo: liquido > 0 ? .receita : .gasto, valor: abs(liquido),
                                     categoria: Transacao.categoriaAjuste, carteira: "",
                                     descricao: "Ajuste de saldo", data: ajustes.map(\.data).max() ?? .now))
            }
            try? ctx.save()
        }
        UserDefaults.standard.set(true, forKey: chave)
    }
}
