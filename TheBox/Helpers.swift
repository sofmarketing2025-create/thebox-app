import SwiftUI

enum Mes {
    static let nomes = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho",
                        "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"]
    static let curtos = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]

    /// Índice do mês: ano * 12 + (mês - 1)
    static func indice(_ date: Date = .now) -> Int {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return (c.year ?? 2026) * 12 + (c.month ?? 1) - 1
    }
    static func nome(_ i: Int) -> String { nomes[i % 12] }
    static func curto(_ i: Int) -> String { curtos[i % 12] }
    static func ano(_ i: Int) -> Int { i / 12 }
    static func chave(_ i: Int) -> String { String(format: "%04d-%02d", i / 12, i % 12 + 1) }

    /// Data de vencimento naquele mês (ajusta dia 31 em meses menores)
    static func data(_ i: Int, dia: Int, hora: Int = 9) -> Date {
        let cal = Calendar.current
        var c = DateComponents()
        c.year = i / 12
        c.month = i % 12 + 1
        c.day = 1
        let primeiro = cal.date(from: c) ?? .now
        let dias = cal.range(of: .day, in: .month, for: primeiro)?.count ?? 28
        c.day = min(dia, dias)
        c.hour = hora
        return cal.date(from: c) ?? primeiro
    }
}

let ptBR = Locale(identifier: "pt_BR")

extension Double {
    var brl: String { formatted(.currency(code: "BRL").locale(ptBR)) }
    var curto: String {
        if self >= 1000 {
            return (self / 1000).formatted(.number.precision(.fractionLength(0...1)).locale(ptBR)) + "k"
        }
        return String(Int(rounded()))
    }
    var textoCampo: String { String(format: "%.2f", self).replacingOccurrences(of: ".", with: ",") }
}

/// Converte "1.234,56" ou "12,5" em número
func lerValor(_ s: String) -> Double? {
    let limpo = s.replacingOccurrences(of: "R$", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: ".", with: "")
        .replacingOccurrences(of: ",", with: ".")
    return Double(limpo)
}

// MARK: - Estilo

extension Color {
    static let fundo = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let cartao = Color(red: 0.115, green: 0.115, blue: 0.125)
    static let cartao2 = Color(white: 0.17)
    static let borda = Color.white.opacity(0.07)
}

struct EstiloCartao: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cartao, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.borda))
    }
}

extension View {
    func cartao() -> some View { modifier(EstiloCartao()) }
}

struct Cabecalho<Acoes: View>: View {
    let sub: String
    let titulo: String
    @ViewBuilder var acoes: () -> Acoes

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sub).font(.system(size: 17)).foregroundStyle(.secondary)
            HStack {
                Text(titulo).font(.system(size: 38, weight: .heavy)).tracking(-0.8)
                Spacer()
                HStack(spacing: 10) { acoes() }
            }
        }
        .padding(.top, 8)
    }
}

struct BotaoMais: View {
    var acao: () -> Void
    var body: some View {
        Button(action: acao) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.cartao, in: Circle())
                .overlay(Circle().stroke(Color.borda))
        }
        .accessibilityLabel("Adicionar")
    }
}

struct SeletorMes: View {
    @Binding var mes: Int
    var body: some View {
        let hoje = Mes.indice()
        Menu {
            Picker("Mês", selection: $mes) {
                ForEach((hoje - 12)...(hoje + 12), id: \.self) { i in
                    Text("\(Mes.nome(i)) \(String(Mes.ano(i)))").tag(i)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(Mes.curto(mes).uppercased()).font(.system(size: 15, weight: .bold)).tracking(1.5)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(Color.cartao, in: Capsule())
            .overlay(Capsule().stroke(Color.borda))
        }
    }
}

struct Chip: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View {
        Text(texto)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.cartao2, in: Capsule())
    }
}

struct Legenda: View {
    let cor: Color
    let texto: String
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(cor).frame(width: 9, height: 9)
            Text(texto).foregroundStyle(.secondary)
        }
    }
}

struct LinhaStat: View {
    let titulo: String
    let valor: String
    var destaque = false
    var body: some View {
        HStack {
            Text(titulo).foregroundStyle(destaque ? .primary : .secondary)
            Spacer()
            Text(valor).fontWeight(destaque ? .bold : .semibold)
        }
        .padding(.vertical, 12)
    }
}

struct Vazio: View {
    let texto: String
    var botao: String? = nil
    var acao: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Text(texto).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let botao, let acao {
                Button(action: acao) {
                    Text(botao).font(.headline).foregroundStyle(.black)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(.white, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.cartao, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PontoMes: Identifiable {
    let mes: Int
    let valor: Double
    var id: Int { mes }
}
