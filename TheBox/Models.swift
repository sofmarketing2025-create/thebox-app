import SwiftUI
import SwiftData
import AppIntents

enum TipoConta: String, Codable, CaseIterable, Identifiable {
    case fixo, parcelado, unico
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .fixo: return "Fixo"
        case .parcelado: return "Parcelado"
        case .unico: return "Única"
        }
    }
}

enum Categoria: String, Codable, CaseIterable, Identifiable, AppEnum {
    case alimentacao, mercado, transporte, casa, saude, lazer, compras, outros
    var id: String { rawValue }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Categoria"
    static var caseDisplayRepresentations: [Categoria: DisplayRepresentation] = [
        .alimentacao: "Alimentação",
        .mercado: "Mercado",
        .transporte: "Transporte",
        .casa: "Casa",
        .saude: "Saúde",
        .lazer: "Lazer",
        .compras: "Compras",
        .outros: "Outros"
    ]

    var nome: String {
        switch self {
        case .alimentacao: return "Alimentação"
        case .mercado: return "Mercado"
        case .transporte: return "Transporte"
        case .casa: return "Casa"
        case .saude: return "Saúde"
        case .lazer: return "Lazer"
        case .compras: return "Compras"
        case .outros: return "Outros"
        }
    }
    var icone: String {
        switch self {
        case .alimentacao: return "fork.knife"
        case .mercado: return "cart"
        case .transporte: return "car"
        case .casa: return "house"
        case .saude: return "cross.case"
        case .lazer: return "gamecontroller"
        case .compras: return "bag"
        case .outros: return "square.grid.2x2"
        }
    }
    var cor: Color {
        switch self {
        case .alimentacao: return .orange
        case .mercado: return .green
        case .transporte: return .blue
        case .casa: return .teal
        case .saude: return .red
        case .lazer: return .purple
        case .compras: return .pink
        case .outros: return .gray
        }
    }
}

enum Pagamento: String, Codable, CaseIterable, Identifiable, AppEnum {
    case credito, debito, pix, dinheiro
    var id: String { rawValue }

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tipo de pagamento"
    static var caseDisplayRepresentations: [Pagamento: DisplayRepresentation] = [
        .credito: "Crédito",
        .debito: "Débito",
        .pix: "Pix",
        .dinheiro: "Dinheiro"
    ]

    var nome: String {
        switch self {
        case .credito: return "Crédito"
        case .debito: return "Débito"
        case .pix: return "Pix"
        case .dinheiro: return "Dinheiro"
        }
    }
}

@Model
final class Conta {
    var nome: String = ""
    var valor: Double = 0
    var dia: Int = 10
    var tipoRaw: String = "fixo"
    /// Fixo: por quantos meses (0 = sem fim). Parcelado: nº de parcelas.
    var meses: Int = 0
    /// Mês de início (ver Mes.indice)
    var inicio: Int = 0
    /// Meses pagos, no formato "2026-10"
    var pagos: [String] = []

    init(nome: String, valor: Double, dia: Int, tipo: TipoConta, meses: Int, inicio: Int) {
        self.nome = nome
        self.valor = valor
        self.dia = dia
        self.tipoRaw = tipo.rawValue
        self.meses = meses
        self.inicio = inicio
        self.pagos = []
    }

    var tipo: TipoConta {
        get { TipoConta(rawValue: tipoRaw) ?? .fixo }
        set { tipoRaw = newValue.rawValue }
    }

    func ocorre(em i: Int) -> Bool {
        let d = i - inicio
        if d < 0 { return false }
        if tipo == .unico { return d == 0 }
        if meses > 0 && d >= meses { return false }
        return true
    }

    func parcela(em i: Int) -> String? {
        guard tipo != .unico, meses > 0 else { return nil }
        return "\(i - inicio + 1)/\(meses)"
    }

    func pago(em i: Int) -> Bool { pagos.contains(Mes.chave(i)) }

    func alternarPago(em i: Int) {
        let k = Mes.chave(i)
        if let x = pagos.firstIndex(of: k) { pagos.remove(at: x) } else { pagos.append(k) }
    }

    func atrasada(em i: Int) -> Bool {
        if pago(em: i) { return false }
        let hoje = Mes.indice()
        if i < hoje { return true }
        return i == hoje && dia < Calendar.current.component(.day, from: .now)
    }
}

@Model
final class Gasto {
    var valor: Double = 0
    var descricao: String = ""
    var categoriaRaw: String = "outros"
    var pagamentoRaw: String = "credito"
    var data: Date = Date.now

    init(valor: Double, descricao: String, categoria: Categoria, pagamento: Pagamento, data: Date = .now) {
        self.valor = valor
        self.descricao = descricao
        self.categoriaRaw = categoria.rawValue
        self.pagamentoRaw = pagamento.rawValue
        self.data = data
    }

    var categoria: Categoria {
        get { Categoria(rawValue: categoriaRaw) ?? .outros }
        set { categoriaRaw = newValue.rawValue }
    }
    var pagamento: Pagamento {
        get { Pagamento(rawValue: pagamentoRaw) ?? .credito }
        set { pagamentoRaw = newValue.rawValue }
    }
    var mes: Int { Mes.indice(data) }
}
