import Foundation
import SwiftData

enum TipoTransacao: String, Codable, CaseIterable, Identifiable {
    case gasto, receita
    var id: String { rawValue }
    var nome: String { self == .gasto ? "Gasto" : "Receita" }
}

enum TipoCarteira: String, Codable, CaseIterable, Identifiable {
    case credito, debito, pix, dinheiro
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .credito: return "Crédito"
        case .debito: return "Débito"
        case .pix: return "Pix"
        case .dinheiro: return "Dinheiro"
        }
    }
    var icone: String {
        switch self {
        case .credito, .debito: return "creditcard"
        case .pix: return "bolt.fill"
        case .dinheiro: return "banknote"
        }
    }
}

@Model
final class Categoria {
    var chave: UUID = UUID()
    var nome: String = ""
    var icone: String = "tag.fill"
    var tipoRaw: String = "gasto"
    /// Quanto pode gastar por mês nessa categoria (0 = sem limite)
    var limite: Double = 0
    /// Essencial (conta, mercado) ou desejo (lazer, compras)
    var essencial: Bool = true
    var ordem: Int = 0

    init(nome: String, icone: String, tipo: TipoTransacao, limite: Double = 0, essencial: Bool = true, ordem: Int = 0) {
        self.nome = nome
        self.icone = icone
        self.tipoRaw = tipo.rawValue
        self.limite = limite
        self.essencial = essencial
        self.ordem = ordem
    }

    var tipo: TipoTransacao { TipoTransacao(rawValue: tipoRaw) ?? .gasto }

    static func iconePadrao(_ nome: String) -> String {
        let n = nome.lowercased().folding(options: .diacriticInsensitive, locale: ptBR)
        let mapa: [(String, String)] = [
            ("aliment", "fork.knife"), ("mercado", "cart.fill"), ("restaurante", "fork.knife"),
            ("transporte", "car.fill"), ("uber", "car.fill"), ("combust", "fuelpump.fill"), ("carro", "car.fill"),
            ("saude", "heart.fill"), ("farmacia", "cross.case.fill"), ("academia", "dumbbell.fill"),
            ("assinatura", "rectangle.stack.fill"), ("lazer", "gamecontroller.fill"), ("viagem", "airplane"),
            ("moradia", "house.fill"), ("casa", "house.fill"), ("aluguel", "house.fill"),
            ("educacao", "book.fill"), ("curso", "book.fill"), ("pet", "pawprint.fill"),
            ("roupa", "tshirt.fill"), ("compra", "bag.fill"), ("presente", "gift.fill"),
            ("salario", "briefcase.fill"), ("freela", "laptopcomputer"), ("invest", "chart.line.uptrend.xyaxis"),
            ("reembolso", "arrow.uturn.backward"), ("venda", "tag.fill"), ("outro", "square.grid.2x2.fill")
        ]
        return mapa.first { n.contains($0.0) }?.1 ?? "tag.fill"
    }
}

@Model
final class Carteira {
    var chave: UUID = UUID()
    var nome: String = ""
    var tipoRaw: String = "credito"
    /// Dia de vencimento da fatura (só cartão de crédito)
    var diaVencimento: Int = 10
    var ordem: Int = 0
    /// Meses com fatura paga, no formato "2026-10"
    var faturasPagas: [String] = []

    init(nome: String, tipo: TipoCarteira, diaVencimento: Int = 10, ordem: Int = 0) {
        self.nome = nome
        self.tipoRaw = tipo.rawValue
        self.diaVencimento = diaVencimento
        self.ordem = ordem
    }

    var tipo: TipoCarteira { TipoCarteira(rawValue: tipoRaw) ?? .credito }
    func faturaPaga(em i: Int) -> Bool { faturasPagas.contains(Mes.chave(i)) }
    func alternarFatura(em i: Int) {
        let k = Mes.chave(i)
        if let x = faturasPagas.firstIndex(of: k) { faturasPagas.remove(at: x) } else { faturasPagas.append(k) }
    }
}

@Model
final class Transacao {
    var chave: UUID = UUID()
    var tipoRaw: String = "gasto"
    var valor: Double = 0
    var categoria: String = ""
    var carteira: String = ""
    var descricao: String = ""
    var data: Date = Date.now

    init(tipo: TipoTransacao, valor: Double, categoria: String, carteira: String, descricao: String, data: Date = .now) {
        self.tipoRaw = tipo.rawValue
        self.valor = valor
        self.categoria = categoria
        self.carteira = carteira
        self.descricao = descricao
        self.data = data
    }

    var tipo: TipoTransacao { TipoTransacao(rawValue: tipoRaw) ?? .gasto }
    var mes: Int { Mes.indice(data) }
    var titulo: String { descricao.isEmpty ? categoria : descricao }

    /// Cópia solta (ainda não salva), usada pra desfazer uma exclusão
    func copia() -> Transacao {
        Transacao(tipo: tipo, valor: valor, categoria: categoria, carteira: carteira, descricao: descricao, data: data)
    }
}

@Model
final class Conta {
    var chave: UUID = UUID()
    var nome: String = ""
    var valor: Double = 0
    var dia: Int = 10
    var venceMesSeguinte: Bool = false
    var categoria: String = ""
    /// Repete todo mês (sem parcelas definidas)
    var repetir: Bool = true
    /// Parcelas: 0 = não é parcelada
    var parcelaAtual: Int = 0
    var totalParcelas: Int = 0
    /// Mês (ver Mes.indice) em que aparece pela primeira vez / da parcela atual
    var inicio: Int = 0
    /// Pagamentos no formato "2026-10|Nubank"
    var pagamentos: [String] = []
    /// Meses apagados só daquele mês ("apagar só essa"), formato "2026-10"
    var excluidos: [String] = []
    /// Parcelas pagas adiantado (saem do fim do parcelamento)
    var adiantadas: Int = 0
    /// Juros ao mês em % (opcional, usado no método avalanche)
    var juros: Double = 0

    init(nome: String, valor: Double, dia: Int, venceMesSeguinte: Bool, categoria: String,
         repetir: Bool, parcelaAtual: Int, totalParcelas: Int, inicio: Int) {
        self.nome = nome
        self.valor = valor
        self.dia = dia
        self.venceMesSeguinte = venceMesSeguinte
        self.categoria = categoria
        self.repetir = repetir
        self.parcelaAtual = parcelaAtual
        self.totalParcelas = totalParcelas
        self.inicio = inicio
    }

    var parcelada: Bool { totalParcelas > 0 }
    var tipoNome: String { parcelada ? "Parcelado" : (repetir ? "Fixo" : "Única") }

    var recorrente: Bool { parcelada || repetir }

    func ocorre(em i: Int) -> Bool {
        if excluidos.contains(Mes.chave(i)) { return false }
        let d = i - inicio
        if d < 0 { return false }
        if parcelada { return max(parcelaAtual, 1) + d <= totalParcelas - adiantadas }
        return repetir || d == 0
    }

    func parcela(em i: Int) -> String? {
        guard parcelada else { return nil }
        return "\(max(parcelaAtual, 1) + i - inicio)/\(totalParcelas)"
    }

    func pagamento(em i: Int) -> String? {
        let prefixo = Mes.chave(i) + "|"
        guard let p = pagamentos.first(where: { $0.hasPrefix(prefixo) }) else { return nil }
        return String(p.dropFirst(prefixo.count))
    }

    func pago(em i: Int) -> Bool { pagamento(em: i) != nil }

    func marcarPago(em i: Int, carteira: String) {
        desmarcar(em: i)
        pagamentos.append(Mes.chave(i) + "|" + carteira)
    }

    func desmarcar(em i: Int) {
        let prefixo = Mes.chave(i) + "|"
        pagamentos.removeAll { $0.hasPrefix(prefixo) }
    }

    /// Tira a conta só desse mês (os outros continuam)
    func excluir(em i: Int) {
        let k = Mes.chave(i)
        if !excluidos.contains(k) { excluidos.append(k) }
    }

    func restaurar(em i: Int) {
        excluidos.removeAll { $0 == Mes.chave(i) }
    }

    /// Cópia solta (ainda não salva), usada pra desfazer uma exclusão
    func copia() -> Conta {
        let c = Conta(nome: nome, valor: valor, dia: dia, venceMesSeguinte: venceMesSeguinte, categoria: categoria,
                      repetir: repetir, parcelaAtual: parcelaAtual, totalParcelas: totalParcelas, inicio: inicio)
        c.pagamentos = pagamentos
        c.excluidos = excluidos
        c.adiantadas = adiantadas
        c.juros = juros
        return c
    }

    func vencimento(em i: Int, hora: Int = 9) -> Date {
        Mes.data(venceMesSeguinte ? i + 1 : i, dia: dia, hora: hora)
    }

    func atrasada(em i: Int) -> Bool {
        if pago(em: i) { return false }
        return vencimento(em: i, hora: 23) < .now
    }
}

/// Limite de gastos do mês. Vale a partir de `mes` até ser trocado.
@Model
final class LimiteMensal {
    var mes: Int = 0
    var valor: Double = 0
    init(mes: Int, valor: Double) {
        self.mes = mes
        self.valor = valor
    }
}

// MARK: - Contas do mês

struct Financas {
    var transacoes: [Transacao] = []
    var contas: [Conta] = []
    var carteiras: [Carteira] = []
    var limites: [LimiteMensal] = []

    func credito(_ nome: String) -> Bool {
        carteiras.first { $0.nome == nome }?.tipo == .credito
    }

    func transacoes(em m: Int) -> [Transacao] { transacoes.filter { $0.mes == m } }

    func receitas(em m: Int) -> Double {
        transacoes(em: m).filter { $0.tipo == .receita }.reduce(0) { $0 + $1.valor }
    }

    func gastosAvulsos(em m: Int) -> Double {
        transacoes(em: m).filter { $0.tipo == .gasto }.reduce(0) { $0 + $1.valor }
    }

    func contasDoMes(_ m: Int) -> [Conta] {
        contas.filter { $0.ocorre(em: m) }.sorted { $0.dia < $1.dia }
    }

    func contasPagas(em m: Int) -> [Conta] {
        contas.filter { $0.ocorre(em: m) && $0.pago(em: m) }
    }

    /// Contas pagas fora do cartão de crédito (saem do saldo na hora)
    func contasPagasFora(em m: Int) -> Double {
        contasPagas(em: m).filter { !credito($0.pagamento(em: m) ?? "") }.reduce(0) { $0 + $1.valor }
    }

    /// Fatura do cartão que vence no mês m: contas pagas com ele no mês anterior
    func fatura(_ c: Carteira, em m: Int) -> Double {
        contas.filter { $0.ocorre(em: m - 1) && $0.pagamento(em: m - 1) == c.nome }.reduce(0) { $0 + $1.valor }
    }

    func cartoes() -> [Carteira] { carteiras.filter { $0.tipo == .credito } }

    func faturasPagas(em m: Int) -> Double {
        cartoes().filter { $0.faturaPaga(em: m) }.reduce(0) { $0 + fatura($1, em: m) }
    }

    /// Saldo de hoje: só o que já entrou e já foi pago
    func saldo(em m: Int) -> Double {
        receitas(em: m) - gastosAvulsos(em: m) - contasPagasFora(em: m) - faturasPagas(em: m)
    }

    /// Contas do mês que ainda não foram marcadas como pagas
    func contasAPagar(em m: Int) -> Double {
        contasDoMes(m).filter { !$0.pago(em: m) }.reduce(0) { $0 + $1.valor }
    }

    func faturasAPagar(em m: Int) -> Double {
        cartoes().filter { !$0.faturaPaga(em: m) }.reduce(0) { $0 + fatura($1, em: m) }
    }

    /// Quanto sobra no fim do mês depois de pagar todas as contas e faturas
    func saldoPrevisto(em m: Int) -> Double {
        saldo(em: m) - contasAPagar(em: m) - faturasAPagar(em: m)
    }

    /// Gastos do mês por categoria (transações + contas pagas)
    func gastoPorCategoria(em m: Int) -> [String: Double] {
        var r: [String: Double] = [:]
        for t in transacoes(em: m) where t.tipo == .gasto { r[t.categoria, default: 0] += t.valor }
        for c in contasPagas(em: m) { r[c.categoria.isEmpty ? "Outros" : c.categoria, default: 0] += c.valor }
        return r
    }

    func gastoTotal(em m: Int) -> Double { gastoPorCategoria(em: m).values.reduce(0, +) }

    func limite(em m: Int) -> Double {
        if let l = limites.filter({ $0.mes <= m }).max(by: { $0.mes < $1.mes }) { return l.valor }
        return limites.min(by: { $0.mes < $1.mes })?.valor ?? 0
    }

    func temDados(em m: Int) -> Bool {
        !transacoes(em: m).isEmpty || !contasPagas(em: m).isEmpty
    }
}
