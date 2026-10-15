import Foundation
import SwiftData

@MainActor
enum Ajuste {
    /// Deixa o saldo (geral ou de uma conta) igual ao valor real do banco.
    /// Troca os ajustes antigos do mês (daquela conta) por um só, com a diferença certa.
    static func igualar(real: Double, atual: Double, carteira: String, mes: Int, fin: Financas, ctx: ModelContext) {
        let semAjuste = atual - fin.ajustes(em: mes, carteira: carteira)
        for t in fin.transacoes(em: mes) where t.ehAjuste && t.carteira == carteira { ctx.delete(t) }
        let diferenca = real - semAjuste
        if abs(diferenca) >= 0.01 {
            ctx.insert(Transacao(tipo: diferenca > 0 ? .receita : .gasto, valor: abs(diferenca),
                                 categoria: Transacao.categoriaAjuste, carteira: carteira,
                                 descricao: carteira.isEmpty ? "Ajuste de saldo" : "Ajuste de saldo · \(carteira)"))
        }
        try? ctx.save()
    }
}
